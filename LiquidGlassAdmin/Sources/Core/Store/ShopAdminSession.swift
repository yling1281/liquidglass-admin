import Foundation
import SwiftUI

// MARK: - 店铺后台会话

/// 店铺后台的登录会话，供界面观察。
///
/// 包一层的原因：`ShopAdminClient` 是纯请求层（不继承 ObservableObject），
/// 界面需要知道「登没登、谁登的、正在登吗」。
@MainActor
final class ShopAdminSession: ObservableObject {

    /// 是否已登录。
    @Published private(set) var isLoggedIn: Bool = false
    /// 登录账号（邮箱）。
    @Published private(set) var account: String?
    /// 正在登录。
    @Published private(set) var isLoggingIn: Bool = false
    /// 登录错误。
    @Published var error: String?

    private let client: ShopAdminClient

    init(client: ShopAdminClient = .shared) {
        self.client = client
        self.isLoggedIn = client.isLoggedIn
        self.account = client.account
    }

    /// 账号密码登录。返回是否成功。
    @discardableResult
    func login(username: String, password: String) async -> Bool {
        error = nil
        isLoggingIn = true
        defer { isLoggingIn = false }

        let message = await client.login(username: username, password: password)
        if let message {
            error = message
            isLoggedIn = false
            return false
        }
        isLoggedIn = true
        account = username
        return true
    }

    /// 退出。
    func logout() {
        client.logout()
        isLoggedIn = false
        account = nil
        error = nil
    }

    /// 重新读一次状态（切回前台、下拉刷新时用）。
    func refresh() async {
        isLoggedIn = client.isLoggedIn
        account = client.account
    }

    /// 改服务器地址后重置。
    func updateBaseURL(_ value: String) {
        client.updateBaseURL(value)
        isLoggedIn = client.isLoggedIn
        account = client.account
    }
}
