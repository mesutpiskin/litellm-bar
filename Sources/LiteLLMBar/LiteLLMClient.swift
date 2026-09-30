import Foundation

enum APIError: LocalizedError {
    case invalidURL
    case http(Int, String)
    case decoding(String)
    case noSessionToken

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Geçersiz sunucu adresi."
        case .http(let code, let body):
            if code == 401 || code == 403 { return "Yetkisiz (\(code)). Anahtar/oturum geçersiz ya da süresi dolmuş olabilir.\n\(body)" }
            return "Sunucu hatası (\(code)): \(body)"
        case .decoding(let msg):
            return "Yanıt çözümlenemedi: \(msg)"
        case .noSessionToken:
            return "Giriş başarılı görünüyor ama oturum anahtarı alınamadı. SSO kullanılıyorsa API anahtarı ile giriş yapın."
        }
    }

    var isNotFound: Bool {
        if case .http(let code, _) = self { return code == 404 }
        return false
    }

    var isUnauthorized: Bool {
        if case .http(let code, _) = self { return code == 401 || code == 403 }
        return false
    }
}

struct SessionInfo {
    let key: String
    let userId: String?
    let userEmail: String?
    let userRole: String?
}

final class LiteLLMClient: NSObject, URLSessionDelegate, URLSessionTaskDelegate {
    let baseURL: URL
    let apiKey: String?
    let allowInsecureTLS: Bool

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.httpShouldSetCookies = false
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()

    init(baseURL: URL, apiKey: String?, allowInsecureTLS: Bool) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.allowInsecureTLS = allowInsecureTLS
    }

    deinit { session.invalidateAndCancel() }

    static func normalize(_ raw: String) -> URL? {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        if s.hasSuffix("/ui") { s.removeLast(3) }
        if !s.lowercased().hasPrefix("http://") && !s.lowercased().hasPrefix("https://") { s = "https://" + s }
        guard let url = URL(string: s), url.host != nil else { return nil }
        return url
    }

    // MARK: Endpoints

    func keyInfo() async throws -> KeyInfoResponse {
        try await get("key/info")
    }

    func userInfo(userId: String) async throws -> UserInfoResponse {
        try await get("user/info", query: [URLQueryItem(name: "user_id", value: userId)])
    }

    func models() async throws -> [String] {
        let res: ModelListResponse = try await get("v1/models")
        return res.data.map(\.id).sorted()
    }

    func dailyActivity(start: String, end: String, apiKeyHash: String?) async throws -> [DailyEntry] {
        var all: [DailyEntry] = []
        var page = 1
        while page <= 20 {
            var q = [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end),
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "page_size", value: "100"),
            ]
            if let apiKeyHash { q.append(URLQueryItem(name: "api_key", value: apiKeyHash)) }
            let res: DailyActivityResponse = try await get("user/daily/activity", query: q)
            all.append(contentsOf: res.results)
            let more = res.metadata?.hasMore
                ?? ((res.metadata?.totalPages ?? 1) > page)
            if !more || res.results.isEmpty { break }
            page += 1
        }
        return all
    }

    /// Logs in with LiteLLM UI credentials and returns the session key embedded in the JWT cookie.
    func login(username: String, password: String) async throws -> SessionInfo {
        // Classic form login: responds with a redirect + `token` cookie.
        var req = URLRequest(url: baseURL.appendingPathComponent("login"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = formEncode(["username": username, "password": password]).data(using: .utf8)
        let (data, resp) = try await session.data(for: req)
        let http = resp as? HTTPURLResponse
        if let http, let token = Self.token(from: http, data: data, url: req.url!) {
            return try Self.decodeSession(jwt: token)
        }
        if let http, http.statusCode == 401 || http.statusCode == 403 {
            throw APIError.http(http.statusCode, Self.message(from: data))
        }

        // Newer versions: JSON login.
        var req2 = URLRequest(url: baseURL.appendingPathComponent("v2/login"))
        req2.httpMethod = "POST"
        req2.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req2.httpBody = try JSONSerialization.data(withJSONObject: ["username": username, "password": password])
        let (data2, resp2) = try await session.data(for: req2)
        if let http2 = resp2 as? HTTPURLResponse {
            if let token = Self.token(from: http2, data: data2, url: req2.url!) {
                return try Self.decodeSession(jwt: token)
            }
            if !(200..<400).contains(http2.statusCode) {
                throw APIError.http(http2.statusCode, Self.message(from: data2))
            }
        }
        throw APIError.noSessionToken
    }

    // MARK: Plumbing

    private func get<T: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> T {
        guard var comps = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !query.isEmpty { comps.queryItems = query }
        guard let url = comps.url else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let apiKey { req.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await session.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw APIError.http(http.statusCode, Self.message(from: data))
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw APIError.decoding("\(path): \(error.localizedDescription)")
        }
    }

    private func formEncode(_ params: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return params.map { k, v in
            "\(k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed) ?? v)"
        }.joined(separator: "&")
    }

    private static func token(from http: HTTPURLResponse, data: Data, url: URL) -> String? {
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { acc, pair in
            if let k = pair.key as? String, let v = pair.value as? String { acc[k] = v }
        }
        if let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: url).first(where: { $0.name == "token" }) {
            return cookie.value
        }
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for k in ["token", "access_token", "jwt"] {
                if let t = json[k] as? String, t.split(separator: ".").count == 3 { return t }
            }
        }
        return nil
    }

    static func decodeSession(jwt: String) throws -> SessionInfo {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else { throw APIError.noSessionToken }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let key = json["key"] as? String else { throw APIError.noSessionToken }
        return SessionInfo(
            key: key,
            userId: json["user_id"] as? String,
            userEmail: json["user_email"] as? String,
            userRole: json["user_role"] as? String
        )
    }

    private static func message(from data: Data) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let err = json["error"] as? [String: Any], let m = err["message"] as? String { return m }
            if let d = json["detail"] as? String { return d }
            if let d = json["detail"] as? [String: Any], let e = d["error"] as? String { return e }
        }
        return String(data: data.prefix(300), encoding: .utf8) ?? ""
    }

    // MARK: URLSession delegate

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Keep the login response (and its Set-Cookie) instead of following redirects to the UI.
        completionHandler(nil)
    }

    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        if allowInsecureTLS,
           challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
           let trust = challenge.protectionSpace.serverTrust {
            completionHandler(.useCredential, URLCredential(trust: trust))
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
