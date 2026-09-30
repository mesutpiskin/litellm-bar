import Foundation

// MARK: - /key/info

struct KeyInfoResponse: Decodable {
    let key: String?
    let info: KeyInfo
}

struct KeyInfo: Decodable {
    let token: String?
    let keyAlias: String?
    let keyName: String?
    let spend: Double?
    let maxBudget: Double?
    let budgetDuration: String?
    let budgetResetAt: String?
    let models: [String]?
    let userId: String?
    let teamId: String?
    let expires: String?
    let tpmLimit: Int?
    let rpmLimit: Int?

    enum CodingKeys: String, CodingKey {
        case token, spend, models, expires
        case keyAlias = "key_alias"
        case keyName = "key_name"
        case maxBudget = "max_budget"
        case budgetDuration = "budget_duration"
        case budgetResetAt = "budget_reset_at"
        case userId = "user_id"
        case teamId = "team_id"
        case tpmLimit = "tpm_limit"
        case rpmLimit = "rpm_limit"
    }
}

// MARK: - /user/info

struct UserInfoResponse: Decodable {
    let userId: String?
    let userInfo: UserInfo?
    let keys: [UserKey]?

    enum CodingKeys: String, CodingKey {
        case keys
        case userId = "user_id"
        case userInfo = "user_info"
    }
}

struct UserInfo: Decodable {
    let userEmail: String?
    let userRole: String?
    let spend: Double?
    let maxBudget: Double?
    let budgetResetAt: String?

    enum CodingKeys: String, CodingKey {
        case spend
        case userEmail = "user_email"
        case userRole = "user_role"
        case maxBudget = "max_budget"
        case budgetResetAt = "budget_reset_at"
    }
}

struct UserKey: Decodable, Identifiable {
    let token: String?
    let keyAlias: String?
    let keyName: String?
    let spend: Double?
    let maxBudget: Double?

    var id: String { token ?? keyName ?? keyAlias ?? UUID().uuidString }
    var displayName: String { keyAlias ?? keyName ?? "İsimsiz anahtar" }

    enum CodingKeys: String, CodingKey {
        case token, spend
        case keyAlias = "key_alias"
        case keyName = "key_name"
        case maxBudget = "max_budget"
    }
}

// MARK: - /v1/models

struct ModelListResponse: Decodable {
    struct Item: Decodable { let id: String }
    let data: [Item]
}

// MARK: - /user/daily/activity

struct DailyActivityResponse: Decodable {
    let results: [DailyEntry]
    let metadata: ActivityMetadata?
}

struct ActivityMetadata: Decodable {
    let hasMore: Bool?
    let totalPages: Int?
    let page: Int?

    enum CodingKeys: String, CodingKey {
        case page
        case hasMore = "has_more"
        case totalPages = "total_pages"
    }
}

struct DailyEntry: Decodable {
    let date: String
    let metrics: Metrics
    let breakdown: Breakdown?
}

struct Breakdown: Decodable {
    // Dictionary keys are model / key names — decoded verbatim (no snake_case conversion).
    let models: [String: BreakdownItem]?
    let apiKeys: [String: BreakdownItem]?

    enum CodingKeys: String, CodingKey {
        case models
        case apiKeys = "api_keys"
    }
}

struct BreakdownItem: Decodable {
    let metrics: Metrics
}

struct Metrics: Decodable {
    var spend: Double = 0
    var promptTokens: Int = 0
    var completionTokens: Int = 0
    var totalTokens: Int = 0
    var apiRequests: Int = 0
    var successfulRequests: Int = 0
    var failedRequests: Int = 0

    enum CodingKeys: String, CodingKey {
        case spend
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case apiRequests = "api_requests"
        case successfulRequests = "successful_requests"
        case failedRequests = "failed_requests"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spend = (try? c.decodeIfPresent(Double.self, forKey: .spend)) ?? 0
        promptTokens = (try? c.decodeIfPresent(Int.self, forKey: .promptTokens)) ?? 0
        completionTokens = (try? c.decodeIfPresent(Int.self, forKey: .completionTokens)) ?? 0
        totalTokens = (try? c.decodeIfPresent(Int.self, forKey: .totalTokens)) ?? 0
        apiRequests = (try? c.decodeIfPresent(Int.self, forKey: .apiRequests)) ?? 0
        successfulRequests = (try? c.decodeIfPresent(Int.self, forKey: .successfulRequests)) ?? 0
        failedRequests = (try? c.decodeIfPresent(Int.self, forKey: .failedRequests)) ?? 0
        if totalTokens == 0 { totalTokens = promptTokens + completionTokens }
    }

    static func + (l: Metrics, r: Metrics) -> Metrics {
        var m = Metrics()
        m.spend = l.spend + r.spend
        m.promptTokens = l.promptTokens + r.promptTokens
        m.completionTokens = l.completionTokens + r.completionTokens
        m.totalTokens = l.totalTokens + r.totalTokens
        m.apiRequests = l.apiRequests + r.apiRequests
        m.successfulRequests = l.successfulRequests + r.successfulRequests
        m.failedRequests = l.failedRequests + r.failedRequests
        return m
    }
}

// MARK: - View models

struct ModelUsage: Identifiable {
    let name: String
    let metrics: Metrics
    var id: String { name }
}

struct DayUsage: Identifiable {
    let date: Date
    let metrics: Metrics
    var id: Date { date }
}

enum UsageRange: Int, CaseIterable, Identifiable {
    case today = 1, week = 7, month = 30, quarter = 90
    var id: Int { rawValue }
    var label: String {
        switch self {
        case .today: return "Bugün"
        case .week: return "7 gün"
        case .month: return "30 gün"
        case .quarter: return "90 gün"
        }
    }
}

enum UsageScope: String, CaseIterable, Identifiable {
    case user, key
    var id: String { rawValue }
    var label: String { self == .user ? "Kullanıcı" : "Bu anahtar" }
}

enum AuthMode: String, CaseIterable, Identifiable {
    case apiKey, password
    var id: String { rawValue }
    var label: String { self == .apiKey ? "API Anahtarı" : "Kullanıcı Adı / Şifre" }
}

enum MenuBarDisplay: String, CaseIterable, Identifiable {
    case icon, todaySpend, todayTokens, totalSpend
    var id: String { rawValue }
    var label: String {
        switch self {
        case .icon: return "Sadece ikon"
        case .todaySpend: return "Bugünkü harcama"
        case .todayTokens: return "Bugünkü token"
        case .totalSpend: return "Toplam harcama"
        }
    }
}
