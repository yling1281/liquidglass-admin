import Foundation

// MARK: - 操作记录

/// 卡密操作记录。
///
/// 实测（`GET /card/record/list`）：
/// ```json
/// {
///   "id": 182, "cardNo": "LG-SSF5-F36U", "action": "REDEEM",
///   "fromStatus": 1, "toStatus": 2, "channelCode": "SELF",
///   "orderNo": "", "account": null, "source": "API",
///   "operator": "client",
///   "remark": "device=AND-... renew=LG-VBC8-DHDA",
///   "createTime": 1792845758
/// }
/// ```
struct CardRecord: Identifiable, Hashable, Decodable {
    let id: Int
    let cardNo: String?
    /// 动作码：`CREATE` / `REDEEM` / `BIND` / `UNBIND` / `FREEZE` / `BAN` 等。
    let action: String?
    let fromStatus: Int?
    let toStatus: Int?
    let channelCode: String?
    let orderNo: String?
    let account: String?
    /// 来源：`API` / `MANUAL` / 渠道名。
    let source: String?
    /// 操作者。`client` 表示插件侧调用，`lingyan` 表示后台人工操作。
    ///
    /// ⚠️ `operator` 是 Swift 保留字（用于自定义运算符），必须用反引号转义。
    /// 加反引号后属性名在 JSON 解码时仍然是 `operator`，与后端字段一致。
    let `operator`: String?
    let remark: String?
    /// 时间戳（**秒**）。
    let createTime: TimeInterval?

    var createDate: Date? {
        guard let createTime, createTime > 0 else { return nil }
        return Date(timeIntervalSince1970: createTime)
    }

    /// 动作的中文名。
    ///
    /// ⚠️ 假设说明：文档未列出完整动作枚举，实测只见到 `CREATE` 与 `REDEEM`。
    /// 这里按前缀/语义做映射，未知的原样显示英文码，不猜错。
    var actionTitle: String {
        switch action {
        case "CREATE": return "生成"
        case "ISSUE": return "发放"
        case "BIND": return "绑定"
        case "UNBIND": return "解绑"
        case "REDEEM": return "核销"
        case "REBIND": return "换绑"
        case "FREEZE": return "冻结"
        case "UNFREEZE": return "解冻"
        case "BAN": return "封禁"
        case "UNBAN": return "解封"
        case "DELETE": return "删除"
        case "RENEW": return "续期"
        case "HEARTBEAT": return "心跳"
        case .some(let raw): return raw
        case nil: return "—"
        }
    }

    /// 来源的中文名。
    var sourceTitle: String {
        switch source {
        case "API": return "接口"
        case "MANUAL": return "手动"
        case .some(let raw): return raw
        case nil: return "—"
        }
    }

    /// 状态变化描述，如「已发放 → 已使用」。
    var statusTransition: String? {
        guard let fromStatus, let toStatus else { return nil }
        let from = CardStatus(rawValue: fromStatus)?.displayName ?? "\(fromStatus)"
        let to = CardStatus(rawValue: toStatus)?.displayName ?? "\(toStatus)"
        return "\(from) → \(to)"
    }
}

// MARK: - 渠道

/// 发卡渠道配置。
///
/// 实测（`GET /card/channel/list`）：
/// ```json
/// { "channelCode": "CAIHONG", "channelName": "彩虹发卡", "enabled": false, "remark": "占位配置，本期不发起外部请求" }
/// ```
struct CardChannel: Identifiable, Hashable, Decodable {
    let channelCode: String
    let channelName: String
    let enabled: Bool
    let remark: String?

    /// 用 `channelCode` 作 id（它是渠道唯一键）。
    var id: String { channelCode }
}

// MARK: - 用户与权限

/// 当前登录用户。
struct AdminUser: Equatable {
    var userId: Int?
    var userName: String
    var nickName: String
    var avatar: String?
    var roles: [String]
    var permissions: [String]

    /// 是否有指定权限点。
    ///
    /// 权限点实测全集：
    /// `card:key:list` / `card:key:generate` / `card:key:status` / `card:key:renew` /
    /// `card:key:remove` / `card:key:secret` / `card:record:list` /
    /// `card:export:add` / `card:channel:list`
    func can(_ permission: String) -> Bool {
        permissions.contains(permission)
    }

    /// 显示名（优先昵称）。
    var displayName: String {
        nickName.isEmpty ? userName : nickName
    }
}

/// 权限点常量。
enum Permission {
    static let cardList = "card:key:list"
    static let cardGenerate = "card:key:generate"
    static let cardStatus = "card:key:status"
    static let cardRenew = "card:key:renew"
    static let cardRemove = "card:key:remove"
    static let cardSecret = "card:key:secret"
    static let recordList = "card:record:list"
    static let exportAdd = "card:export:add"
    static let channelList = "card:channel:list"
}

// MARK: - 统计

/// 卡密统计。
///
/// ⚠️ 假设说明：**服务端没有专门的统计接口**。
/// 前端首页是用三次 `list` 请求的 `total` 相加算出来的：
/// ```js
/// list({pageNum:1,pageSize:1})                  → total 总数
/// list({pageNum:1,pageSize:1,status:0})         → total 未发放
/// list({pageNum:1,pageSize:1,status:1})         → total 已发放
/// ```
/// 本工程沿用同一策略（`CardStatisticsStore`），保证数字与网页后台一致。
/// 「在线设备数」「今日激活数」需要按 `expireAt`/`createTime` 拉全量后本地算，
/// 代价较高 —— 因此这两项走**近似口径**并在界面上标注，不谎称是精确值。
struct CardStatistics: Equatable {
    var total: Int = 0
    var unissued: Int = 0
    var issued: Int = 0
    var used: Int = 0
    var frozen: Int = 0
    var voided: Int = 0
    var expired: Int = 0

    /// 已激活（= 已发放 + 已使用）。
    var activated: Int { issued + used }

    /// 未激活（= 未发放）。
    var notActivated: Int { unissued }

    /// 在线设备数（近似口径：已绑定的卡数，见 `CardStatisticsStore` 说明）。
    var onlineDevices: Int = 0

    /// 今日激活数（近似口径：今日 createTime 的卡数）。
    var todayActivated: Int = 0

    /// 到期预警数（7 天内到期）。
    var expiringSoon: Int = 0
}
