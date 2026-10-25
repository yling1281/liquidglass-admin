import Foundation

// MARK: - 服务端配置

/// 可运行时修改的服务地址。
struct ServerConfig: Codable, Equatable {
    var cardAPIBase: String
    var shopAPIBase: String
    var shopAdminAPIBase: String

    static let `default` = ServerConfig(
        cardAPIBase: AppConfig.defaultCardAPIBase,
        shopAPIBase: AppConfig.defaultShopAPIBase,
        shopAdminAPIBase: AppConfig.defaultShopAdminAPIBase
    )

    /// 去掉结尾多余的 `/`，避免拼出 `//login`。
    var normalizedCardAPIBase: String { trimTrailingSlash(cardAPIBase) }
    var normalizedShopAPIBase: String { trimTrailingSlash(shopAPIBase) }
    var normalizedShopAdminAPIBase: String { trimTrailingSlash(shopAdminAPIBase) }

    private func trimTrailingSlash(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while out.hasSuffix("/") { out.removeLast() }
        return out
    }
}

/// 服务地址的持久化。
final class ServerConfigStore {
    static let shared = ServerConfigStore()

    private let defaults: UserDefaults
    private let key = "lg_admin_server_config"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var config: ServerConfig {
        get {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode(ServerConfig.self, from: data)
            else { return .default }
            return decoded
        }
        set {
            guard let data = try? JSONEncoder().encode(newValue) else { return }
            defaults.set(data, forKey: key)
        }
    }

    func resetToDefault() {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - 请求描述

/// 一次网络请求的完整描述。
struct APIRequest {
    var endpoint: Endpoint
    /// query 参数（GET 用）。值为 nil 的键会被忽略。
    var query: [String: String?] = [:]
    /// JSON body（POST / PUT 用）。
    ///
    /// 编码方式分两种：
    /// - `.json`：JSON 编码（卡密后台用）。
    /// - `.form`：`application/x-www-form-urlencoded`（**商城前台用**）。
    ///
    /// ⚠️ 实测结论：商城前台（`siyecaogf.cn`）的 POST 接口走 jQuery 默认的
    /// `contentType: application/x-www-form-urlencoded`。用 JSON 提交会得到
    /// 「商品不存在#1」这类**误导性**错误（服务端按表单解析，拿不到 `item_id`）。
    var body: Body?
    /// 目标服务域。
    var service: Service = .card

    /// 请求体编码方式。
    enum Body {
        case json([String: Any])
        case form([String: Any])

        /// 字典形式（方便与既有代码兼容）。
        var dictionary: [String: Any] {
            switch self {
            case .json(let d): return d
            case .form(let d): return d
            }
        }
    }

    /// 服务域 —— 决定用哪个 base URL。
    enum Service {
        /// 卡密后台（`.../prod-api`）
        case card
        /// 商城前台（`www.siyecaogf.cn`）
        case shop
        /// 店铺后台（`lgk3f9x2p.lingyan.cyou`）
        case shopAdmin
    }
}

extension APIRequest {
    /// 便捷构造：JSON body（传字典，自动按 JSON 编码）。
    ///
    /// ⚠️ 不要再加一个 `body: Body?` 版本的便利 init ——
    /// 它会和编译器合成的成员初始化器 `(endpoint:query:body:service:)`
    /// 在「省略 query」时形成完全相同的签名，调用点报 `ambiguous use of 'init'`。
    /// 需要指定编码方式时直接用成员初始化器：
    /// `APIRequest(endpoint: e, body: .form([...]), service: .shop)`
    init(endpoint: Endpoint, body: [String: Any]?, query: [String: String?] = [:], service: Service = .card) {
        self.init(endpoint: endpoint, query: query, body: body.map { Body.json($0) }, service: service)
    }
}

// MARK: - 统一请求层

/// 统一网络请求层。
///
/// 职责：
/// 1. **鉴权** —— 需要鉴权的端点自动加 `Authorization: Bearer <token>`；
///    收到 401 / code 401 时清空登录态并回调 `onUnauthorized`。
/// 2. **错误处理** —— 把 HTTP 层错误、传输层错误、业务 `code != 200`、解析失败
///    统一收敛成 `APIError`，UI 层只处理一种错误类型。
/// 3. **加载与失败重试** —— 网络抖动类错误（`.transport` / 5xx / 429）自动重试，
///    退避间隔递增；业务错误不重试。
///
/// 线程安全：内部状态变更都切回主线程，调用方可直接在 `@MainActor` 里 `await`。
actor APIClient {

    static let shared = APIClient()

    private let session: URLSession
    private let tokenStore: TokenStore
    private let serverStore: ServerConfigStore

    /// 重试次数（不含首次尝试）。
    private let maxRetries = 2
    /// 首次退避间隔。
    private let baseRetryDelay: TimeInterval = 0.6

    /// 收到 401 时触发（主线程）。用于登出并切回登录页。
    ///
    /// ⚠️ actor 隔离属性，**不能**从外部直接赋值
    /// （会报 "actor-isolated property 'onUnauthorized' can not be mutated from the main actor"）。
    /// 通过 `setUnauthorizedHandler(_:)` 设置。
    private var onUnauthorized: (@MainActor @Sendable () -> Void)?

    /// 设置 401 回调（跨 actor 安全）。
    func setUnauthorizedHandler(_ handler: (@MainActor @Sendable () -> Void)?) {
        onUnauthorized = handler
    }

    init(
        session: URLSession = APIClient.makeSession(),
        tokenStore: TokenStore = .shared,
        serverStore: ServerConfigStore = .shared
    ) {
        self.session = session
        self.tokenStore = tokenStore
        self.serverStore = serverStore
    }

    private static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AppConfig.requestTimeout
        config.timeoutIntervalForResource = AppConfig.requestTimeout * 2
        config.waitsForConnectivity = false
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }

    // MARK: 基础请求

    /// 发起一次请求并解析业务载荷。
    ///
    /// - Parameter type: 期望从 `data`（或顶层 `rows`）里解出的类型。
    /// - Returns: 成功时返回载荷值。
    /// - Throws: `APIError`。业务错误不重试，网络类错误按 `maxRetries` 重试。
    func send<T: Decodable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        let data = try await sendRaw(request)
        do {
            let envelope = try JSONDecoder().decode(APIEnvelope<T>.self, from: data)
            guard envelope.isSuccess else {
                // 后端约定：code 401 表示登录态失效。
                if envelope.code == 401 {
                    await handleUnauthorized()
                    throw APIError.unauthorized
                }
                throw APIError.business(code: envelope.code, message: envelope.msg)
            }
            guard let payload = envelope.payload else {
                // code 200 但没有载荷：部分接口（如解冻）只关心 msg/data.success，
                // 对泛型 T 无法解码的情况由调用方改用 `sendRaw`。
                throw APIError.decoding("响应缺少 data 字段")
            }
            return payload
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
    }

    /// 发起请求并返回原始 JSON 数据（用于需要自定义解包或只要 msg 的场景）。
    func sendRaw(_ request: APIRequest) async throws -> Data {
        var lastError: APIError = .transport("未知错误")

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await perform(request)

                guard let http = response as? HTTPURLResponse else {
                    throw APIError.transport("响应不是 HTTP")
                }

                // HTTP 层失败：401 走登出逻辑，其余按状态码判定是否可重试。
                guard (200..<300).contains(http.statusCode) else {
                    let message = Self.errorMessage(from: data)
                    if http.statusCode == 401 {
                        await handleUnauthorized()
                        throw APIError.unauthorized
                    }
                    let error = APIError.http(status: http.statusCode, message: message)
                    if error.isRetryable, attempt < maxRetries {
                        lastError = error
                        try await sleepBeforeRetry(attempt)
                        continue
                    }
                    throw error
                }

                // HTTP 200 但业务 code 可能是 401 —— 先看一眼再决定。
                if let code = Self.businessCode(from: data), code == 401 {
                    await handleUnauthorized()
                    throw APIError.unauthorized
                }

                return data
            } catch let error as APIError {
                lastError = error
                if error.isRetryable, attempt < maxRetries {
                    try await sleepBeforeRetry(attempt)
                    continue
                }
                throw error
            } catch is CancellationError {
                throw APIError.cancelled
            } catch let urlError as URLError {
                if urlError.code == .cancelled {
                    throw APIError.cancelled
                }
                lastError = .transport(urlError.localizedDescription)
                if attempt < maxRetries {
                    try await sleepBeforeRetry(attempt)
                    continue
                }
                throw lastError
            } catch {
                lastError = .transport(error.localizedDescription)
                if attempt < maxRetries {
                    try await sleepBeforeRetry(attempt)
                    continue
                }
                throw lastError
            }
        }

        throw lastError
    }

    // MARK: 底层

    private func perform(_ request: APIRequest) async throws -> (Data, URLResponse) {
        let url = try buildURL(for: request)

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.endpoint.method.rawValue
        urlRequest.timeoutInterval = AppConfig.requestTimeout
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        urlRequest.setValue("LiquidGlassAdmin/1.0 (iOS)", forHTTPHeaderField: "User-Agent")

        if request.endpoint.requiresAuth {
            if let token = tokenStore.token, !token.isEmpty {
                urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            }
        }

        if request.endpoint.method != .get, let body = request.body {
            switch body {
            case .json(let dict):
                guard JSONSerialization.isValidJSONObject(dict) else {
                    throw APIError.decoding("请求体不是合法 JSON")
                }
                urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
                urlRequest.httpBody = try JSONSerialization.data(withJSONObject: dict)

            case .form(let dict):
                urlRequest.setValue(
                    "application/x-www-form-urlencoded; charset=UTF-8",
                    forHTTPHeaderField: "Content-Type"
                )
                urlRequest.httpBody = Self.formEncoded(dict)
            }
        }

        let (data, response) = try await session.data(for: urlRequest)
        return (data, response)
    }

    private func buildURL(for request: APIRequest) throws -> URL {
        let base: String
        switch request.service {
        case .card: base = serverStore.config.normalizedCardAPIBase
        case .shop: base = serverStore.config.normalizedShopAPIBase
        case .shopAdmin: base = serverStore.config.normalizedShopAdminAPIBase
        }

        guard var components = URLComponents(string: base + request.endpoint.path) else {
            throw APIError.transport("服务器地址无效：\(base)")
        }

        // query：过滤掉 nil 值。
        var items: [URLQueryItem] = []
        for (key, value) in request.query {
            if let value, !value.isEmpty {
                items.append(URLQueryItem(name: key, value: value))
            }
        }
        if !items.isEmpty {
            components.queryItems = items
        }

        guard let url = components.url else {
            throw APIError.transport("URL 拼接失败")
        }
        return url
    }

    private func handleUnauthorized() async {
        tokenStore.clear()
        // 先把回调取到局部变量再进 MainActor：
        // `onUnauthorized` 是 actor 隔离属性，直接写在 `MainActor.run` 闭包里
        // 会被判定为「跨 actor 访问」，编译报
        // "actor-isolated property 'onUnauthorized' can not be referenced from the main actor"。
        let callback = onUnauthorized
        await MainActor.run { callback?() }
    }

    private func sleepBeforeRetry(_ attempt: Int) async throws {
        // 指数退避：0.6s → 1.2s
        let delay = baseRetryDelay * pow(2, Double(attempt))
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }

    // MARK: 解析辅助

    /// 把字典编码成 `application/x-www-form-urlencoded`。
    ///
    /// 商城前台（羁序工坊）的 POST 接口用的是 jQuery 默认的表单编码，
    /// 键值需按 RFC 3986 转义（空格 → `+` 是表单惯例，特殊字符要百分号编码）。
    static func formEncoded(_ dict: [String: Any]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // 表单编码里空格用 `+` 表示，其余非保留字符走百分号编码。
        let encoded = dict
            .sorted { $0.key < $1.key }
            .map { key, value -> String in
                let text: String
                switch value {
                case let v as String: text = v
                case let v as Int: text = String(v)
                case let v as Double: text = String(v)
                case let v as Bool: text = v ? "true" : "false"
                case is NSNull: text = ""
                default: text = "\(value)"
                }
                let escaped = text.addingPercentEncoding(withAllowedCharacters: allowed)?
                    .replacingOccurrences(of: "%20", with: "+") ?? text
                return "\(key)=\(escaped)"
            }
            .joined(separator: "&")
        return Data(encoded.utf8)
    }

    /// 从错误响应里尽力提取 `msg`。
    private static func errorMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return String(data: data, encoding: .utf8) ?? ""
        }
        return (object["msg"] as? String) ?? (object["message"] as? String) ?? ""
    }

    /// 提取业务 `code`（只关心是否为 401，不做完整解码）。
    private static func businessCode(from data: Data) -> Int? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object["code"] as? Int
    }
}
