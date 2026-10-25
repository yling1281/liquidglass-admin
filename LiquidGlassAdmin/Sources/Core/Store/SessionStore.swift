import Foundation
import SwiftUI

// MARK: - 加载状态

/// 通用的异步加载状态。
///
/// 覆盖 UI 需要的四种态：空闲 / 加载中 / 成功 / 失败（可重试）。
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(APIError)

    var value: Value? {
        if case .loaded(let v) = self { return v }
        return nil
    }

    var error: APIError? {
        if case .failed(let e) = self { return e }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }

    /// 是否处于「首次加载」（此时显示居中 loading 而非保留旧数据）。
    var isInitialLoad: Bool {
        if case .loading = self { return true }
        return false
    }
}

// MARK: - 会话

/// 登录会话。
///
/// 负责：登录、登出、token 持久化、自动登录、用户信息与权限。
@MainActor
final class SessionStore: ObservableObject {

    @Published private(set) var isAuthenticated: Bool = false
    @Published private(set) var user: AdminUser?
    @Published private(set) var permissions: [String] = []
    @Published var loginError: APIError?
    @Published private(set) var isLoggingIn: Bool = false

    private let client: APIClient
    private let tokenStore: TokenStore
    private let serverStore: ServerConfigStore

    /// 记录是否已经尝试过自动登录（避免视图反复触发）。
    private var didAttemptAutoLogin = false

    init(
        client: APIClient = .shared,
        tokenStore: TokenStore = .shared,
        serverStore: ServerConfigStore = .shared
    ) {
        self.client = client
        self.tokenStore = tokenStore
        self.serverStore = serverStore

        // APIClient 是 actor，回调必须通过它的方法设置（不能直接赋值 actor 属性）。
        Task { [weak self] in
            await client.setUnauthorizedHandler {
                Task { @MainActor in
                    self?.handleUnauthorized()
                }
            }
        }
    }

    /// 尝试用已保存的 token 自动登录。
    ///
    /// - Returns: 是否成功。
    func attemptAutoLogin() async -> Bool {
        guard !didAttemptAutoLogin else { return isAuthenticated }
        didAttemptAutoLogin = true

        guard tokenStore.isValid else {
            tokenStore.clear()
            return false
        }

        isAuthenticated = true   // 先乐观进入，靠 fetchUserInfo 纠正

        do {
            try await fetchUserInfo()
            return true
        } catch {
            if case APIError.unauthorized = error {
                tokenStore.clear()
                isAuthenticated = false
            }
            return isAuthenticated
        }
    }

    /// 登录。
    func login(username: String, password: String) async {
        loginError = nil
        isLoggingIn = true
        defer { isLoggingIn = false }

        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.login,
                body: ["username": username, "password": password]
            ))

            let envelope = try JSONDecoder().decode(LoginEnvelope.self, from: data)
            guard envelope.code == 200 else {
                loginError = .business(code: envelope.code, message: envelope.msg)
                return
            }
            guard let token = envelope.resolvedToken, !token.isEmpty else {
                loginError = .decoding("响应中没有 token")
                return
            }

            tokenStore.save(token: token)
            isAuthenticated = true
            didAttemptAutoLogin = true

            // 拉一次用户信息（失败不影响登录本身，只是权限为空）。
            try? await fetchUserInfo()
        } catch let error as APIError {
            loginError = error
        } catch {
            loginError = .transport(error.localizedDescription)
        }
    }

    /// 拉取当前用户信息与权限点。
    func fetchUserInfo() async throws {
        let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.userInfo))
        let envelope = try JSONDecoder().decode(UserInfoEnvelope.self, from: data)
        guard envelope.code == 200 else {
            throw APIError.business(code: envelope.code, message: envelope.msg)
        }

        let profile = envelope.user
        user = AdminUser(
            userId: profile?.userId,
            userName: profile?.userName ?? "—",
            nickName: profile?.nickName ?? "",
            avatar: profile?.avatar,
            roles: envelope.roles ?? [],
            permissions: envelope.permissions ?? []
        )
        permissions = envelope.permissions ?? []
    }

    /// 登出。
    func logout() {
        tokenStore.clear()
        user = nil
        permissions = []
        isAuthenticated = false
        didAttemptAutoLogin = false
    }

    private func handleUnauthorized() {
        guard isAuthenticated else { return }
        logout()
    }

    /// 是否拥有权限点。
    func can(_ permission: String) -> Bool {
        permissions.contains(permission)
    }

    // MARK: - QQ 登录

    /// QQ 绑定状态。
    struct QQBinding: Equatable {
        var bound: Bool = false
        var nickname: String = ""
        var figureurl: String = ""
        var openidMasked: String = ""
        /// 当前账号是不是管理员（只有管理员能绑定/用 QQ 登录）。
        var isAdmin: Bool = false
        /// 服务端有没有配 QQ（缺 qq_config.json 时为 false）。
        var configured: Bool = false
    }

    /// 用 QQ 回调里拿到的卡密 token 完成登录。
    ///
    /// 这个 token 是服务端 `/qq/callback` 用 `token_for()` 签的，
    /// 与账号密码登录拿到的是同一种 JWT，所以走同一套落库与拉权限流程。
    func loginWithQQToken(_ token: String) async {
        loginError = nil
        guard !token.isEmpty else {
            loginError = .decoding("QQ 回调里没有 token")
            return
        }
        tokenStore.save(token: token)
        isAuthenticated = true
        didAttemptAutoLogin = true
        do {
            try await fetchUserInfo()
        } catch let error as APIError {
            // token 已落地，但拉不到权限 —— 如实暴露，不假装成功
            loginError = error
        } catch {
            loginError = .transport(error.localizedDescription)
        }
    }

    /// 读当前账号的 QQ 绑定状态。
    func loadQQStatus() async -> QQBinding? {
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.qqStatus))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  (obj["code"] as? Int) == 200,
                  let d = obj["data"] as? [String: Any]
            else { return nil }
            return QQBinding(
                bound: (d["bound"] as? Bool) ?? false,
                nickname: (d["nickname"] as? String) ?? "",
                figureurl: (d["figureurl"] as? String) ?? "",
                openidMasked: (d["openidMasked"] as? String) ?? "",
                isAdmin: (d["isAdmin"] as? Bool) ?? false,
                configured: (d["configured"] as? Bool) ?? false
            )
        } catch {
            return nil
        }
    }

    /// 取绑定票据，返回要打开的授权页地址。
    func requestQQBindURL() async -> Result<URL, APIError> {
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.qqBindTicket))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return .failure(.decoding("响应不是 JSON"))
            }
            let code = (obj["code"] as? Int) ?? -1
            guard code == 200 else {
                return .failure(.business(code: code, message: (obj["msg"] as? String) ?? "取绑定票据失败"))
            }
            guard let d = obj["data"] as? [String: Any],
                  let path = d["url"] as? String
            else {
                return .failure(.decoding("绑定地址缺失"))
            }
            // 服务端给的是 `/qq/authorize?t=…` 相对路径，拼上 API 根。
            let full = path.hasPrefix("http")
                ? path
                : serverStore.config.normalizedCardAPIBase + path
            guard let url = URL(string: full) else {
                return .failure(.decoding("绑定地址不合法：\(full)"))
            }
            return .success(url)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    /// 解绑 QQ。
    func unbindQQ() async -> String? {
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.qqUnbind))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return "解绑失败：响应异常"
            }
            let code = (obj["code"] as? Int) ?? -1
            if code == 200 {
                return nil
            }
            return (obj["msg"] as? String) ?? "解绑失败（code \(code)）"
        } catch let error as APIError {
            return error.errorDescription
        } catch {
            return error.localizedDescription
        }
    }

    // MARK: - 账号打通

    /// 账号关联信息（当前卡密账号对应店铺后台的哪个管理员）。
    struct AccountLink: Equatable {
        var userName: String = ""
        var linked: Bool = false
        var manageId: Int = 0
        var email: String = ""
        var nickname: String = ""
        /// 店铺后台的接口能力是否可用（容器在跑、PHP 能调）。
        var ready: Bool = false
    }

    /// 读账号关联。
    func loadAccountLink() async -> AccountLink? {
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.accountLink))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let d = obj["data"] as? [String: Any]
            else { return nil }
            return AccountLink(
                userName: (d["userName"] as? String) ?? "",
                linked: (d["linked"] as? Bool) ?? false,
                manageId: (d["manageId"] as? Int) ?? 0,
                email: (d["email"] as? String) ?? "",
                nickname: (d["nickname"] as? String) ?? "",
                ready: (d["acgReady"] as? Bool) ?? false
            )
        } catch {
            return nil
        }
    }

    /// 修改密码。
    ///
    /// 服务端会**同时**改两个后台：卡密后台（sqlite, sha256）和店铺后台
    /// （MySQL, bcrypt）。返回的文案直接来自服务端，会明确说
    /// 「两个后台的密码都已更新」还是「只有卡密改了、店铺同步失败」——
    /// 跨两个库没有事务，不能假装原子成功。
    func changePassword(old: String, new: String) async -> (message: String, isError: Bool) {
        let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 6 else {
            return ("新密码至少 6 位", true)
        }
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.changePassword,
                body: ["oldPassword": old, "newPassword": new]
            ))
            guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                return ("响应格式异常", true)
            }
            let code = (obj["code"] as? Int) ?? -1
            let msg = (obj["msg"] as? String) ?? ""
            if code == 200 {
                return (msg.isEmpty ? "密码已修改" : msg, false)
            }
            return (msg.isEmpty ? "修改失败（code \(code)）" : msg, true)
        } catch let error as APIError {
            return (error.errorDescription ?? "修改失败", true)
        } catch {
            return (error.localizedDescription, true)
        }
    }

}
