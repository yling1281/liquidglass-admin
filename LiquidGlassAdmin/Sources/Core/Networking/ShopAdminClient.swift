import Foundation

// MARK: - 店铺后台客户端

/// 店铺后台（acg-faka / 异次元发卡）的 API 客户端。
///
/// 为什么不能复用 `APIClient`：两套系统的鉴权方式**根本不同**。
///
/// | | 卡密后台 | 店铺后台 |
/// |---|---|---|
/// | 鉴权 | `Authorization: Bearer <JWT>` | **Cookie `MANAGE_USER`** |
/// | 编码 | JSON | **form-urlencoded** |
/// | 额外要求 | 无 | **必须带同域 Referer** |
///
/// 三条都是实测踩出来的：
/// 1. 用 JSON 提交，PHP 的 `$_POST` 取不到参数 —— 登录会报「该邮箱不存在」，
///    但账号其实是对的。这个假错误骗了很久。
/// 2. 不带 Referer，`App\Interceptor\ManageSession::handle` 会判定为跨站请求，
///    直接返回「当前页面会话失效，请刷新网页..」—— 即使 cookie 完全正确。
/// 3. Cookie 名是 `MANAGE_USER`，值是 base64 后的 JWT（签名密钥是管理员密码哈希）。
@MainActor
final class ShopAdminClient {

    static let shared = ShopAdminClient()

    /// 店铺后台的错误。
    enum ShopAdminError: LocalizedError {
        case notLoggedIn
        case sessionExpired
        case business(code: Int, message: String)
        case transport(String)
        case decoding(String)

        var errorDescription: String? {
            switch self {
            case .notLoggedIn:
                return "还没登录店铺后台"
            case .sessionExpired:
                return "店铺后台会话已过期，请到「设置」里重新登录"
            case .business(_, let message):
                return message
            case .transport(let message):
                return "网络错误：\(message)"
            case .decoding(let message):
                return "数据解析失败：\(message)"
            }
        }
    }

    /// 仓库地址（可在设置里改）。
    private var baseURL: String

    /// 登录账号（仅用于界面回显）。
    private(set) var account: String?

    /// 是否已登录。
    var isLoggedIn: Bool { cookieValue() != nil }

    private let session: URLSession

    private static let cookieName = "MANAGE_USER"
    private static let accountKey = "shopadmin.account"

    init(baseURL: String = AppConfig.defaultShopAdminAPIBase) {
        self.baseURL = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.account = UserDefaults.standard.string(forKey: Self.accountKey)

        let config = URLSessionConfiguration.default
        // 用系统 cookie 存储：它能正确处理多个 `Set-Cookie`（`allHeaderFields`
        // 会把它们合并成一个字符串，按苹果文档拆是不可靠的）。
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.timeoutIntervalForRequest = AppConfig.requestTimeout
        config.timeoutIntervalForResource = AppConfig.requestTimeout * 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)

        restoreCookieIfNeeded()
    }

    /// 修改服务器地址（设置页用）。
    func updateBaseURL(_ value: String) {
        baseURL = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        restoreCookieIfNeeded()
    }

    // MARK: - Cookie 管理

    private func cookieValue() -> String? {
        guard let url = URL(string: baseURL) else { return nil }
        return HTTPCookieStorage.shared
            .cookies(for: url)?
            .first { $0.name == Self.cookieName }?
            .value
    }

    /// 冷启动恢复会话。
    ///
    /// `HTTPCookieStorage` 在 iOS 上是持久化的，但它可能被系统清理；
    /// 我们自己再存一份到 UserDefaults，启动时补回去。
    private func restoreCookieIfNeeded() {
        guard cookieValue() == nil else { return }
        guard let saved = UserDefaults.standard.string(forKey: "shopadmin.cookie.\(baseURL)"),
              !saved.isEmpty,
              let url = URL(string: baseURL),
              let cookie = HTTPCookie(properties: [
                  .name: Self.cookieName,
                  .value: saved,
                  .domain: url.host ?? "",
                  .path: "/",
                  .secure: "TRUE"
              ])
        else { return }
        HTTPCookieStorage.shared.setCookie(cookie)
    }

    private func persistCookie() {
        guard let value = cookieValue() else { return }
        UserDefaults.standard.set(value, forKey: "shopadmin.cookie.\(baseURL)")
    }

    /// 退出登录。
    func logout() {
        if let url = URL(string: baseURL),
           let cookies = HTTPCookieStorage.shared.cookies(for: url) {
            for cookie in cookies where cookie.name == Self.cookieName {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        UserDefaults.standard.removeObject(forKey: "shopadmin.cookie.\(baseURL)")
        UserDefaults.standard.removeObject(forKey: Self.accountKey)
        account = nil
    }

    // MARK: - 登录

    /// 账号密码登录。成功返回 `nil`，失败返回可直接展示的错误文案。
    ///
    /// 店铺后台的「用户名」实际是邮箱（`acg_manage.email` 是唯一键）——
    /// 与卡密后台的 `lingyan` 不是同一个登录名，但**密码相同**。
    /// 现在卡密后台加了邮箱别名，一套凭证可以进两个后台。
    @discardableResult
    func login(username: String, password: String) async -> String? {
        var request = makeRequest(path: "/admin/api/authentication/login", method: "POST")
        request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = Self.formEncode([
            "username": username,
            "password": password,
            "remember": "1"
        ])

        do {
            let (data, _) = try await session.data(for: request, referer: baseURL + "/admin/authentication/login")
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "登录响应不是 JSON"
            }
            let code = (object["code"] as? Int) ?? -1
            guard code == 200 else {
                return (object["msg"] as? String) ?? "登录失败（code \(code)）"
            }
            persistCookie()
            guard isLoggedIn else {
                return "登录成功但没拿到会话 Cookie（服务端未下发 \(Self.cookieName)）"
            }
            account = username
            UserDefaults.standard.set(username, forKey: Self.accountKey)
            return nil
        } catch {
            return "网络错误：\(error.localizedDescription)"
        }
    }

    // MARK: - 通用请求

    /// 调一个后台接口，返回 `data` 原始对象。
    ///
    /// acg-faka 的响应统一是 `{code, msg, data}`；列表接口的 `data`
    /// 形如 `{list: [...], total: N}`。
    func request(
        path: String,
        method: String = "GET",
        query: [String: String] = [:],
        body: [String: String] = [:],
        refererPage: String = "/admin/dashboard/index"
    ) async throws -> Any {

        guard isLoggedIn else { throw ShopAdminError.notLoggedIn }

        var fullPath = path
        if !query.isEmpty, method == "GET" {
            let encoded = query
                .sorted { $0.key < $1.key }
                .map { "\(Self.percentEncode($0.key))=\(Self.percentEncode($0.value))" }
                .joined(separator: "&")
            fullPath += (fullPath.contains("?") ? "&" : "?") + encoded
        }

        var request = makeRequest(path: fullPath, method: method)
        if method != "GET", !body.isEmpty {
            request.setValue("application/x-www-form-urlencoded; charset=utf-8",
                             forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formEncode(body)
        }

        let data: Data
        do {
            (data, _) = try await session.data(for: request, referer: baseURL + refererPage)
            persistCookie()   // 服务端可能续期
        } catch {
            throw ShopAdminError.transport(error.localizedDescription)
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ShopAdminError.decoding("响应不是 JSON")
        }
        let code = (object["code"] as? Int) ?? -1
        let message = (object["msg"] as? String) ?? ""

        if code == 200 {
            // 括号不能省：写成 `object["data"] ?? [:] as [String: Any]` 会被解析成
            // `(object["data"] ?? [:]) as [String: Any]`，data 是数组时直接崩。
            return object["data"] ?? ([:] as [String: Any])
        }
        if message.contains("会话失效") || message.contains("登录会话过期") {
            logout()
            throw ShopAdminError.sessionExpired
        }
        throw ShopAdminError.business(code: code, message: message.isEmpty ? "请求失败" : message)
    }

    /// 列表接口的便捷封装，返回 `(items, total)`。
    ///
    /// ⚠️ **列表接口是 POST，不是 GET。**
    ///
    /// `Admin\Api\Commodity::data()` 里写的是 `$map = $_POST;`，
    /// 分页（`page` / `limit`）和筛选条件全部从 **POST body** 读。
    /// 用 GET query 传这些参数不会有任何效果 —— 服务端照常返回全部数据，
    /// 看起来「能用」，但分页永远不生效、筛选永远不过滤。
    /// 实测：GET `?page=2&limit=2` 返回全部 4 条；POST 同样参数才正确返回第 2 页。
    ///
    /// 各模块的列表项字段完全不同，所以保持 `[String: Any]`，
    /// 由上层按模块配置渲染 —— 23 个模块共用这一份请求逻辑。
    func list(
        path: String,
        query: [String: String] = [:],
        refererPage: String = "/admin/dashboard/index"
    ) async throws -> (items: [[String: Any]], total: Int) {
        let payload = try await request(
            path: path,
            method: "POST",
            body: query,
            refererPage: refererPage
        )
        guard let dict = payload as? [String: Any] else { return ([], 0) }
        let items = (dict["list"] as? [[String: Any]]) ?? []
        let total = (dict["total"] as? Int)
            ?? Int((dict["total"] as? String) ?? "")
            ?? items.count
        return (items, total)
    }

    // MARK: - 底层

    private func makeRequest(path: String, method: String) -> URLRequest {
        let url = URL(string: baseURL + path) ?? URL(string: baseURL)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) "
            + "AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        return request
    }

    static func formEncode(_ body: [String: String]) -> Data {
        let text = body
            .map { "\(percentEncode($0.key))=\(percentEncode($0.value))" }
            .joined(separator: "&")
        return Data(text.utf8)
    }

    /// 严格按 RFC 3986 的 unreserved 集合编码。
    private static func percentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

// MARK: - Referer 注入

extension URLSession {

    /// 发请求，并强制带上 `Referer`。
    ///
    /// 为什么必须单独包一层：acg-faka 的 API 拦截器会对比
    /// `Referer` 的 host 与当前站点 host，不一致直接判会话失效。
    /// 这不是可选头，是必需头。
    fileprivate func data(for request: URLRequest, referer: String) async throws -> (Data, URLResponse) {
        var mutable = request
        mutable.setValue(referer, forHTTPHeaderField: "Referer")
        mutable.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        return try await self.data(for: mutable)
    }
}
