import Foundation

// MARK: - 服务地址

/// 后台服务地址配置。
///
/// 依据：`docs/后台接口与功能说明.md`。
/// 所有地址均可在「设置」页运行时修改并持久化，方便切换测试/生产环境。
enum AppConfig {

    /// 卡密后台 API 根（文档「卡密 API 根」）。
    static let defaultCardAPIBase = "https://z7k2m9xq.lingyan.cyou/prod-api"

    /// 卡密后台网页版（仅用于「关于/帮助」外链）。
    static let defaultCardAdminWeb = "https://z7k2m9xq.lingyan.cyou/"

    /// 商城前台 API 根（商品/分类）。
    static let defaultShopAPIBase = "https://www.siyecaogf.cn"

    /// 店铺后台 API 根。
    /// 实测登录端点为 `/admin/api/authentication/login`。
    static let defaultShopAdminAPIBase = "https://lgk3f9x2p.lingyan.cyou"

    /// 商城前台网页版。
    static let defaultShopWeb = "https://www.siyecaogf.cn/"

    /// 登录时默认填入的账号（仅作首启预填，用户可改）。
    static let defaultUsername = "lingyan"

    /// 请求超时（秒）。
    static let requestTimeout: TimeInterval = 20
}

// MARK: - 统一响应包装

/// 后端统一响应格式。
///
/// 文档已验证的返回形如：
/// ```json
/// { "code": 200, "msg": "操作成功", "token": "..." }
/// { "code": 200, "msg": "查询成功", "rows": [...], "total": 34, "pageNum": 1, "pageSize": 20 }
/// ```
///
/// ⚠️ 假设说明：
/// - 后端在业务失败时返回 `code != 200`（实测「接口不存在」为 `code: 2001`），
///   但 HTTP 状态码始终是 200。因此**判定失败必须看 `code`，不能只看 HTTP 状态**。
/// - `code == 200` 统一视为成功；`code == 401` 视为登录态失效（约定值，见 `APIError.unauthorized`）。
struct APIEnvelope<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: T?

    var isSuccess: Bool { code == 200 }

    /// 业务载荷。
    ///
    /// 注意：列表接口的 `rows` / `total` 是**顶层数组**，与 `data: T?` 类型不同，
    /// 不能放在同一个泛型包装里（`data ?? rows` 会编译失败）。
    /// 列表一律走 `sendRaw` + `PagedResponse<T>` 单独解码，见 `APIEndpoint` 的注释。
    var payload: T? { data }
}

/// 登录接口的专用返回（token 在顶层，同时也在 `data.token` 里冗余一份）。
struct LoginEnvelope: Decodable {
    let code: Int
    let msg: String
    let token: String?
    let data: LoginData?

    struct LoginData: Decodable {
        let token: String?
    }

    /// 优先取顶层 token，取不到再退回 `data.token`（文档里两者都有）。
    var resolvedToken: String? {
        if let t = token, !t.isEmpty { return t }
        if let t = data?.token, !t.isEmpty { return t }
        return nil
    }
}

/// `GET /getInfo` 的返回（用户信息 + 权限点）。
struct UserInfoEnvelope: Decodable {
    let code: Int
    let msg: String
    let user: UserProfile?
    let roles: [String]?
    let permissions: [String]?

    struct UserProfile: Decodable {
        let userId: Int?
        let userName: String?
        let nickName: String?
        let avatar: String?
    }
}

// MARK: - 错误类型

/// 统一的网络 / 业务错误。
enum APIError: LocalizedError, Equatable {
    /// 业务返回 code != 200。携带后端原始 message。
    case business(code: Int, message: String)
    /// HTTP 层失败（4xx / 5xx / 无响应）。
    case http(status: Int, message: String)
    /// 登录态失效（token 过期或被踢），需要重新登录。
    case unauthorized
    /// 传输层错误（断网、超时、DNS 等）。
    case transport(String)
    /// 响应无法解析成预期结构。
    case decoding(String)
    /// 请求被取消。
    case cancelled

    var errorDescription: String? {
        switch self {
        case .business(let code, let message):
            return "\(message)（code \(code)）"
        case .http(let status, let message):
            return message.isEmpty ? "服务器返回 HTTP \(status)" : "\(message)（HTTP \(status)）"
        case .unauthorized:
            return "登录已失效，请重新登录"
        case .transport(let message):
            return "网络错误：\(message)"
        case .decoding(let message):
            return "数据解析失败：\(message)"
        case .cancelled:
            return "请求已取消"
        }
    }

    /// 是否值得自动重试（网络抖动类）。
    var isRetryable: Bool {
        switch self {
        case .transport:
            return true
        case .http(let status, _):
            return status >= 500 || status == 429
        default:
            return false
        }
    }
}
