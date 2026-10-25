import AuthenticationServices
import SwiftUI
import UIKit

// MARK: - QQ 授权会话

/// QQ 授权登录的 URL Scheme。
///
/// 服务端 `/prod-api/qq/callback` 换完 openid 后会 302 到这里：
/// - 登录成功：`lingyankey://login?token=<卡密后台 JWT>`
/// - 未绑定：  `lingyankey://login?error=not_bound`
/// - 非管理员：`lingyankey://login?error=not_admin`
/// - 绑定成功：`lingyankey://bind?ok=1`
enum QQCallback {
    static let scheme = "lingyankey"

    /// 从回调 URL 里解出的结果。
    struct Payload {
        var token: String?
        var error: String?
        var isBind: Bool

        /// 错误码转人话。
        var errorMessage: String? {
            guard let error else { return nil }
            switch error {
            case "not_bound":
                return "这个 QQ 还没绑定管理员账号。请先用账号密码登录，到「设置 → QQ 登录」里绑定。"
            case "not_admin":
                return "这个 QQ 绑定的账号没有管理权限。"
            default:
                return error
            }
        }
    }

    static func parse(_ url: URL) -> Payload? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = (url.host ?? "").lowercased()
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }
        return Payload(
            token: value("token"),
            error: value("error"),
            isBind: host == "bind"
        )
    }
}

// MARK: - 错误

enum QQAuthError: LocalizedError {
    case cancelled
    case cannotStart
    case badCallback
    case server(String)

    var errorDescription: String? {
        switch self {
        case .cancelled: return "已取消 QQ 登录"
        case .cannotStart: return "无法打开 QQ 授权页，请稍后重试"
        case .badCallback: return "QQ 返回的数据不完整"
        case .server(let msg): return msg
        }
    }
}

// MARK: - 授权会话

/// 用 `ASWebAuthenticationSession` 打开网页授权，拿到 `lingyankey://` 回调。
///
/// 为什么用系统会话而不是自己拼 Safari：
/// 1. 它是系统弹窗，能直接拦截自定义 scheme 回调，不用注册 Universal Link；
/// 2. 用户能看到地址栏，确认是在给 `graph.qq.com` 授权，不会误以为 App 在偷密码；
/// 3. Cookie 与 Safari 隔离（`prefersEphemeralWebBrowserSession = false` 时共享，
///    这里设 false 以便同一次会话里保持登录态）。
@MainActor
final class QQAuthSession: NSObject {

    /// 全局共享实例。
    ///
    /// 不能写成 `private let qqAuth = QQAuthSession()` 放在 View 里 ——
    /// SwiftUI 的 View 是 struct，随时可能被重建，旧实例会连同正在跑的
    /// `ASWebAuthenticationSession` 一起被释放，回调永远不回来
    /// （表现就是点了 QQ 登录一直转圈）。
    static let shared = QQAuthSession()

    private var session: ASWebAuthenticationSession?

    /// 打开授权页，返回回调 URL。
    func authenticate(url: URL) async throws -> QQCallback.Payload {
        let callback = try await run(url: url)
        guard let payload = QQCallback.parse(callback) else {
            throw QQAuthError.badCallback
        }
        return payload
    }

    private func run(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<URL, Error>) in
            var finished = false
            func finish(_ result: Result<URL, Error>) {
                // 防止 start() 失败和回调同时触发，造成"重复 resume"崩溃
                guard !finished else { return }
                finished = true
                cont.resume(with: result)
            }

            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: QQCallback.scheme
            ) { callbackURL, error in
                if let error {
                    let ns = error as NSError
                    if ns.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                        finish(.failure(QQAuthError.cancelled))
                    } else {
                        finish(.failure(QQAuthError.server(error.localizedDescription)))
                    }
                    return
                }
                guard let callbackURL else {
                    finish(.failure(QQAuthError.badCallback))
                    return
                }
                finish(.success(callbackURL))
            }

            session.presentationContextProvider = self
            // false：复用 Safari 的 Cookie，用户 QQ 已是登录态时能一次点完
            session.prefersEphemeralWebBrowserSession = false

            self.session = session

            if !session.start() {
                finish(.failure(QQAuthError.cannotStart))
            }
        }
    }
}

// MARK: - 呈现上下文

extension QQAuthSession: ASWebAuthenticationPresentationContextProviding {

    nonisolated func presentationAnchor(
        for session: ASWebAuthenticationSession
    ) -> ASPresentationAnchor {
        // 取当前活跃的 key window。iOS 15+ 用 connectedScenes；
        // 找不到就退化成新建一个空 window，保证不会崩。
        let scenes = UIApplication.shared.connectedScenes
        let active = scenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }

        if let window = active?.windows.first(where: \.isKeyWindow) {
            return window
        }
        if let window = active?.windows.first {
            return window
        }
        if let scene = active {
            return UIWindow(windowScene: scene)
        }
        return ASPresentationAnchor()
    }
}
