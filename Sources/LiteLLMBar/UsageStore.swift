import Foundation
import ServiceManagement
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    enum Screen { case dashboard, login, settings }

    // Persisted settings
    @AppStorage("baseURL") var baseURLString = ""
    @AppStorage("authMode") var authModeRaw = AuthMode.apiKey.rawValue
    @AppStorage("username") var username = ""
    @AppStorage("allowInsecureTLS") var allowInsecureTLS = false
    @AppStorage("refreshMinutes") var refreshMinutes = 5 { didSet { scheduleTimer() } }
    @AppStorage("menuBarDisplay") var menuBarDisplayRaw = MenuBarDisplay.todaySpend.rawValue
    @AppStorage("range") private var rangeRaw = UsageRange.week.rawValue
    @AppStorage("scope") private var scopeRaw = UsageScope.user.rawValue

    @Published var screen: Screen = .dashboard
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var lastUpdated: Date?

    @Published var keyInfo: KeyInfo?
    @Published var userInfo: UserInfoResponse?
    @Published var availableModels: [String] = []
    @Published var days: [DayUsage] = []
    @Published var modelUsage: [ModelUsage] = []
    @Published var totals = Metrics()
    @Published var today = Metrics()
    @Published var activityUnsupported = false

    private var sessionKey: String?   // key obtained via username/password login (not persisted as API key)
    private var timer: Timer?

    var authMode: AuthMode {
        get { AuthMode(rawValue: authModeRaw) ?? .apiKey }
        set { authModeRaw = newValue.rawValue }
    }
    var menuBarDisplay: MenuBarDisplay {
        get { MenuBarDisplay(rawValue: menuBarDisplayRaw) ?? .todaySpend }
        set { menuBarDisplayRaw = newValue.rawValue; objectWillChange.send() }
    }
    var range: UsageRange {
        get { UsageRange(rawValue: rangeRaw) ?? .week }
        set { rangeRaw = newValue.rawValue; Task { await refresh() } }
    }
    var scope: UsageScope {
        get { UsageScope(rawValue: scopeRaw) ?? .user }
        set { scopeRaw = newValue.rawValue; Task { await refresh() } }
    }

    var effectiveKey: String? {
        authMode == .apiKey ? Keychain.get("apiKey") : (sessionKey ?? Keychain.get("sessionKey"))
    }
    var isConfigured: Bool { LiteLLMClient.normalize(baseURLString) != nil && effectiveKey != nil }
    var host: String { LiteLLMClient.normalize(baseURLString)?.host ?? "" }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                errorMessage = "Oturum açılışında başlatma ayarlanamadı: \(error.localizedDescription)"
            }
            objectWillChange.send()
        }
    }

    init() {
        if !isConfigured { screen = .login }
        scheduleTimer()
        Task { await refresh() }
    }

    // MARK: Auth

    func loginWithAPIKey(baseURL: String, apiKey: String) async -> Bool {
        guard let url = LiteLLMClient.normalize(baseURL) else { errorMessage = APIError.invalidURL.errorDescription; return false }
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        defer { isLoading = false }
        do {
            _ = try await LiteLLMClient(baseURL: url, apiKey: key, allowInsecureTLS: allowInsecureTLS).keyInfo()
            baseURLString = url.absoluteString
            authMode = .apiKey
            Keychain.set(key, for: "apiKey")
            errorMessage = nil
            screen = .dashboard
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func loginWithPassword(baseURL: String, username: String, password: String, remember: Bool) async -> Bool {
        guard let url = LiteLLMClient.normalize(baseURL) else { errorMessage = APIError.invalidURL.errorDescription; return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let session = try await LiteLLMClient(baseURL: url, apiKey: nil, allowInsecureTLS: allowInsecureTLS)
                .login(username: username, password: password)
            baseURLString = url.absoluteString
            authMode = .password
            self.username = username
            sessionKey = session.key
            Keychain.set(session.key, for: "sessionKey")
            Keychain.set(remember ? password : nil, for: "password")
            errorMessage = nil
            screen = .dashboard
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// Session keys from UI login expire; transparently re-login when a password is remembered.
    private func reloginIfPossible() async -> Bool {
        guard authMode == .password, let url = LiteLLMClient.normalize(baseURLString),
              let password = Keychain.get("password"), !username.isEmpty else { return false }
        guard let session = try? await LiteLLMClient(baseURL: url, apiKey: nil, allowInsecureTLS: allowInsecureTLS)
            .login(username: username, password: password) else { return false }
        sessionKey = session.key
        Keychain.set(session.key, for: "sessionKey")
        return true
    }

    func logout() {
        Keychain.set(nil, for: "apiKey")
        Keychain.set(nil, for: "sessionKey")
        Keychain.set(nil, for: "password")
        sessionKey = nil
        keyInfo = nil
        userInfo = nil
        availableModels = []
        days = []
        modelUsage = []
        totals = Metrics()
        today = Metrics()
        lastUpdated = nil
        errorMessage = nil
        screen = .login
    }

    // MARK: Refresh

    func scheduleTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, refreshMinutes) * 60)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
    }

    func refresh(retried: Bool = false) async {
        guard let url = LiteLLMClient.normalize(baseURLString), let key = effectiveKey else { return }
        let client = LiteLLMClient(baseURL: url, apiKey: key, allowInsecureTLS: allowInsecureTLS)
        isLoading = true
        defer { isLoading = false }

        do {
            let info = try await client.keyInfo().info
            keyInfo = info

            async let modelsTask = try? client.models()
            async let userTask: UserInfoResponse? = {
                guard let uid = info.userId else { return nil }
                return try? await client.userInfo(userId: uid)
            }()

            let (start, end) = dateBounds()
            let hash = scope == .key ? info.token : nil
            do {
                let entries = try await client.dailyActivity(start: start, end: end, apiKeyHash: hash)
                aggregate(entries, todayString: end)
                activityUnsupported = false
            } catch let e as APIError where e.isNotFound {
                activityUnsupported = true
                aggregate([], todayString: end)
            }

            availableModels = await modelsTask ?? availableModels
            userInfo = await userTask
            lastUpdated = Date()
            errorMessage = nil
        } catch let e as APIError where e.isUnauthorized && !retried {
            if await reloginIfPossible() {
                await refresh(retried: true)
            } else {
                errorMessage = e.localizedDescription
                if authMode == .password { screen = .login }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func dateBounds() -> (String, String) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let now = Date()
        let start = cal.date(byAdding: .day, value: -(range.rawValue - 1), to: now) ?? now
        return (Self.dayFormatter.string(from: start), Self.dayFormatter.string(from: now))
    }

    private func aggregate(_ entries: [DailyEntry], todayString: String) {
        var byDay: [String: Metrics] = [:]
        var byModel: [String: Metrics] = [:]
        for e in entries {
            byDay[e.date, default: Metrics()] = byDay[e.date, default: Metrics()] + e.metrics
            for (name, item) in e.breakdown?.models ?? [:] {
                byModel[name, default: Metrics()] = byModel[name, default: Metrics()] + item.metrics
            }
        }
        days = byDay.compactMap { k, v in Self.dayFormatter.date(from: k).map { DayUsage(date: $0, metrics: v) } }
            .sorted { $0.date < $1.date }
        modelUsage = byModel.map { ModelUsage(name: $0.key, metrics: $0.value) }
            .sorted { ($0.metrics.spend, $0.metrics.totalTokens) > ($1.metrics.spend, $1.metrics.totalTokens) }
        totals = byDay.values.reduce(Metrics(), +)
        today = byDay[todayString] ?? Metrics()
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: Menu bar label

    var menuBarText: String? {
        guard isConfigured, lastUpdated != nil else { return nil }
        switch menuBarDisplay {
        case .icon: return nil
        case .todaySpend: return Fmt.money(today.spend)
        case .todayTokens: return Fmt.tokens(today.totalTokens)
        case .totalSpend: return Fmt.money(userInfo?.userInfo?.spend ?? keyInfo?.spend ?? 0)
        }
    }
}

enum Fmt {
    static func money(_ v: Double) -> String {
        if v == 0 { return "$0" }
        if v < 0.01 { return String(format: "$%.4f", v) }
        if v < 100 { return String(format: "$%.2f", v) }
        return String(format: "$%.0f", v)
    }

    static func tokens(_ v: Int) -> String {
        let d = Double(v)
        switch d {
        case 1_000_000_000...: return String(format: "%.1fB", d / 1_000_000_000)
        case 1_000_000...: return String(format: "%.1fM", d / 1_000_000)
        case 1_000...: return String(format: "%.1fK", d / 1_000)
        default: return "\(v)"
        }
    }

    static func number(_ v: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "tr_TR")
        return f.string(from: NSNumber(value: v)) ?? "\(v)"
    }

    static func date(_ iso: String?) -> String? {
        guard let iso else { return nil }
        let parsers: [ISO8601DateFormatter] = {
            let a = ISO8601DateFormatter()
            a.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let b = ISO8601DateFormatter()
            return [a, b]
        }()
        guard let d = parsers.lazy.compactMap({ $0.date(from: iso) }).first else { return iso }
        let out = DateFormatter()
        out.locale = Locale(identifier: "tr_TR")
        out.dateStyle = .medium
        out.timeStyle = .short
        return out.string(from: d)
    }
}
