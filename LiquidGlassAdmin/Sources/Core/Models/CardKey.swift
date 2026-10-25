import Foundation

// MARK: - 卡密状态

/// 卡密状态机。
///
/// 状态码来自前端 `index-DV5pxiEP.js` 的下拉定义，并经服务端 `statusName` 字段核对：
/// 0 未发放 / 1 已发放 / 2 已使用 / 3 已冻结 / 4 已作废 / 5 已过期。
enum CardStatus: Int, CaseIterable, Identifiable, Codable {
    case unissued = 0
    case issued = 1
    case used = 2
    case frozen = 3
    case voided = 4
    case expired = 5

    var id: Int { rawValue }

    /// 展示名（与服务端 `statusName` 一致）。
    var displayName: String {
        switch self {
        case .unissued: return "未发放"
        case .issued: return "已发放"
        case .used: return "已使用"
        case .frozen: return "已冻结"
        case .voided: return "已作废"
        case .expired: return "已过期"
        }
    }

    /// 前端下拉框里就是用这些字符串作为 value 传给后端的。
    var apiValue: String { String(rawValue) }

    /// 语义色（跟随 iOS 系统色，深浅色模式自适应）。
    var tintName: String {
        switch self {
        case .unissued: return "gray"
        case .issued: return "blue"
        case .used: return "green"
        case .frozen: return "orange"
        case .voided: return "red"
        case .expired: return "red"
        }
    }

    /// 是否为「终端状态」—— 已使用 / 已作废 / 已过期 不再可操作。
    var isTerminal: Bool {
        switch self {
        case .used, .voided, .expired: return true
        default: return false
        }
    }

    /// 是否可以被冻结/封禁。
    var canBeRestricted: Bool {
        switch self {
        case .unissued, .issued: return true
        default: return false
        }
    }
}

// MARK: - 卡密模型

/// 一条卡密记录。
///
/// 字段与实测响应 **一一对应**（`GET /card/key/list` 的 `rows` 元素）：
/// ```json
/// {
///   "id": 86, "batchNo": "B202610245D61D", "cardNo": "LG-SSF5-F36U",
///   "secretMask": "****-****-F36U", "productCode": "LG-APP",
///   "status": 2, "statusName": "已使用", "channelCode": "SELF",
///   "orderNo": null, "bindAccount": null,
///   "bindDevice": "AND-33b13f6dc63dd88c63d3a9d0",
///   "bindCount": 1, "maxBind": 1,
///   "expireAt": 68968057788, "durationDays": 740991,
///   "createTime": 1792836303, "remark": ""
/// }
/// ```
struct CardKey: Identifiable, Hashable, Codable {

    let id: Int
    let batchNo: String?
    let cardNo: String
    let secretMask: String?
    let productCode: String?

    /// 数字状态码。
    let status: Int
    /// 服务端给的中文状态名（权威，优先于本地枚举）。
    let statusName: String?

    let channelCode: String?
    let orderNo: String?
    let bindAccount: String?
    let bindDevice: String?
    let bindCount: Int?
    let maxBind: Int?

    /// 到期时间戳（**秒**）。
    /// ⚠️ 实测确认：服务端用**秒**（`createTime=1792836303` → 2026-10-24 18:05:03 CST），
    /// 而前端 `new Date(n * 1e3)` 把它当毫秒处理 —— 前端那处是**秒→毫秒**换算，
    /// 本工程统一按秒解码。
    let expireAt: TimeInterval?
    /// 有效天数。`740991` 天 ≈ 2029 年，属「超长有效期」卡。
    let durationDays: Int?

    /// 创建时间戳（**秒**）。
    let createTime: TimeInterval?
    let remark: String?

    /// 状态枚举（未知状态码回落到 nil，前端按原始 statusName 显示）。
    var cardStatus: CardStatus? { CardStatus(rawValue: status) }

    /// 展示用的状态名。
    var statusTitle: String {
        statusName ?? cardStatus?.displayName ?? "未知(\(status))"
    }

    /// 到期日期。
    var expireDate: Date? {
        guard let expireAt, expireAt > 0 else { return nil }
        return Date(timeIntervalSince1970: expireAt)
    }

    /// 创建日期。
    var createDate: Date? {
        guard let createTime, createTime > 0 else { return nil }
        return Date(timeIntervalSince1970: createTime)
    }

    /// 剩余天数（负数表示已过期）。
    var remainingDays: Int? {
        guard let expireDate else { return nil }
        let seconds = expireDate.timeIntervalSinceNow
        return Int(seconds / 86400.0)
    }

    /// 是否永久有效（到期时间超过 100 年）。
    ///
    /// ⚠️ 假设说明：服务端用 `durationDays = 740991`（≈2029 年）表示「超长期卡」，
    /// 另有实测 `expireAt` 落在 4155 年。前端对 `expireAt` 为空/0 的处理是显示「永久」。
    /// 本工程按「剩余天数 > 36500（100 年）」判定为永久，与前端 `G()` 函数的语义保持一致。
    var isPermanent: Bool {
        guard let remainingDays else { return false }
        return remainingDays > 36500
    }

    /// 绑定的设备码（Android 侧形如 `AND-<hex>`；iOS 侧形如 `IOS-<hex>`）。
    var deviceDisplay: String {
        if let bindDevice, !bindDevice.isEmpty { return bindDevice }
        return "未绑定"
    }
}

// MARK: - 分页查询

/// 卡密列表的查询条件。
struct CardQuery: Equatable {
    var pageNum: Int = 1
    var pageSize: Int = 20
    /// 搜索关键字。前端是**同一个输入框**，后端按「卡号或批次」处理：
    /// 前端代码 `o.keyword && (n.cardNo = o.keyword, n.batchNo = o.keyword)` ——
    /// 注意它把 keyword **同时**赋给了 cardNo 和 batchNo 两个参数。
    /// 本工程沿用同样策略：两个参数都带上，服务端按其中一个匹配。
    var keyword: String = ""
    /// 状态筛选（空 = 全部）。
    var status: CardStatus?

    /// 组装成 query 字典。
    func queryItems() -> [String: String?] {
        var items: [String: String?] = [
            "pageNum": String(pageNum),
            "pageSize": String(pageSize),
        ]
        if !keyword.isEmpty {
            items["cardNo"] = keyword
            items["batchNo"] = keyword
        }
        if let status {
            items["status"] = status.apiValue
        }
        return items
    }
}

// MARK: - 列表响应

/// 分页列表响应。
///
/// 实测形状：`{code, msg, rows: [...], total, pageNum, pageSize}`。
struct PagedResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let rows: [T]
    let total: Int
    let pageNum: Int
    let pageSize: Int
}

// MARK: - 生成卡密

/// 批量生成卡密的请求参数。
///
/// 实测（前端 `index-DV5pxiEP.js`）：
/// ```js
/// { batchName: "默认批次", productId: "LG-APP", count: 50, durationDays: 30 }
/// ```
/// 注意字段名是 **`durationDays`**，不是 `days`。
struct CardGenerateRequest {
    var batchName: String
    var productId: String
    var count: Int
    var durationDays: Int

    /// 可选的天数档位。
    ///
    /// ⚠️ 假设说明：文档写的是「天卡/月卡/年卡/永久」，但服务端只接受任意整数天数，
    /// 没有枚举校验。前端默认值是 30，这里提供快捷档位并允许自定义输入。
    static let presets: [(label: String, days: Int)] = [
        ("天卡", 1),
        ("周卡", 7),
        ("月卡", 30),
        ("季卡", 90),
        ("年卡", 365),
        ("三年卡", 1095),
        ("十年卡", 3650),
        ("永久（100 年）", 36500),
    ]

    var body: [String: Any] {
        [
            "batchName": batchName,
            "productId": productId,
            "count": count,
            "durationDays": durationDays,
        ]
    }
}

/// 生成成功的返回。
///
/// 实测：`{"code":200,"msg":"生成成功","data":{"batchNo":"B2026102550E4A","successCount":1,"taskId":null}}`
struct CardGenerateResult: Decodable {
    let batchNo: String?
    let successCount: Int?
    /// 异步任务 id。实测为 null（当前为同步生成）；保留以兼容将来改成异步。
    let taskId: String?
}

// MARK: - 状态变更

/// 修改卡密状态的请求。
///
/// 实测：`PUT /card/key/status` body `{ids:[87], status:3, reason:"测试"}`
/// → `{"code":200,"msg":"操作完成","data":{"success":1,"skipped":[]}}`
struct CardStatusRequest {
    var ids: [Int]
    var status: CardStatus
    /// 操作原因。前端用 `reason || "后台操作"` 兜底。
    var reason: String

    var body: [String: Any] {
        [
            "ids": ids,
            "status": status.rawValue,
            "reason": reason.isEmpty ? "后台操作" : reason,
        ]
    }
}

/// 批量操作的返回。
///
/// 实测：
/// - 状态变更 `{"code":200,"msg":"操作完成","data":{"success":1,"skipped":[{"cardNo":"999999","reason":"不存在"}]}}`
/// - 解冻 `{"msg":"已解冻 0 张","data":{"success":0}}`（无 skipped 字段）
/// - 解封 `{"msg":"已解封 1 张","data":{"success":1}}`
/// - 删除 `{"msg":"已删除 0 条","data":{"success":0}}`
struct BatchOperationResult: Decodable {
    let success: Int?
    /// 被跳过的条目。实测是**对象数组** `{cardNo, reason}`，不是字符串数组。
    let skipped: [SkippedEntry]?

    /// 跳过的条目。
    struct SkippedEntry: Decodable, Hashable {
        let cardNo: String?
        let reason: String?
    }

    /// 跳过的卡号列表（供界面直接展示）。
    var skippedCardNos: [String] {
        (skipped ?? []).compactMap { $0.cardNo }
    }

    /// 跳过的原因描述（拼成一行）。
    var skippedDescription: String {
        (skipped ?? [])
            .compactMap { entry in
                guard let reason = entry.reason else { return nil }
                if let cardNo = entry.cardNo { return "\(cardNo)：\(reason)" }
                return reason
            }
            .joined(separator: "；")
    }
}
