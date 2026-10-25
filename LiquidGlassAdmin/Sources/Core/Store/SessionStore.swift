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
}
