import Foundation

// MARK: - Token 存储

/// 登录令牌的持久化。
///
/// 用 `UserDefaults` 而非 Keychain：
/// 令牌是**服务端签发的短期会话凭据**（JWT，文档实测 `exp` 存在），
/// 有效期以小时计；且本 App 的威胁模型是「设备丢失」，Keychain 的额外保护收益有限。
/// 若后续要支持「设备丢失后远程踢下线」，应改用 Keychain + 服务端令牌吊销列表。
final class TokenStore {

    static let shared = TokenStore()

    private let defaults: UserDefaults
    private let tokenKey = "lg_admin_token"
    private let expiryKey = "lg_admin_token_expiry"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// 当前令牌（无则 nil）。
    var token: String? {
        get { defaults.string(forKey: tokenKey) }
        set {
            if let newValue, !newValue.isEmpty {
                defaults.set(newValue, forKey: tokenKey)
            } else {
                defaults.removeObject(forKey: tokenKey)
            }
        }
    }

    /// 令牌过期时间（秒级时间戳）。未记录时返回 nil。
    var expiry: Date? {
        get {
            let raw = defaults.double(forKey: expiryKey)
            return raw > 0 ? Date(timeIntervalSince1970: raw) : nil
        }
        set {
            if let newValue {
                defaults.set(newValue.timeIntervalSince1970, forKey: expiryKey)
            } else {
                defaults.removeObject(forKey: expiryKey)
            }
        }
    }

    /// 保存令牌，同时解析 JWT 的 `exp` 供「自动登录」判断有效期。
    ///
    /// JWT 结构为 `header.payload.signature`，payload 是 base64url 编码的 JSON。
    /// 解析失败不阻断登录（令牌仍然可用），只是拿不到过期时间。
    func save(token: String) {
        self.token = token
        self.expiry = Self.jwtExpiry(from: token)
    }

    /// 清空登录态。
    func clear() {
        token = nil
        expiry = nil
    }

    /// 令牌是否仍然可用。
    ///
    /// - 令牌存在，且
    /// - 过期时间未知（解析不出来）或尚未到期。
    ///
    /// ⚠️ 留 60 秒余量，避免「刚过期的瞬间」还在用。
    var isValid: Bool {
        guard let token, !token.isEmpty else { return false }
        guard let expiry else { return true }
        return expiry.timeIntervalSinceNow > 60
    }

    /// 解析 JWT payload 里的 `exp`。
    static func jwtExpiry(from token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }

        var payload = String(parts[1])
        // base64url → base64：补位 + 换字符
        payload = payload.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = object["exp"] as? Double
        else { return nil }

        return Date(timeIntervalSince1970: exp)
    }
}
