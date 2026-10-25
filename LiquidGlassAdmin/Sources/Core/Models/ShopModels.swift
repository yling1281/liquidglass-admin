import Foundation

// MARK: - 商城响应包装

/// 商城列表响应。
///
/// 实测：`{"code":200,"msg":"success","data":[...],"total":4}`
struct ShopListResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String
    let data: [T]?
    let total: Int?
}

/// 商城数据包装响应（`data` 是对象而非数组）。
///
/// 实测：`{"code":200,"data":{"stock":"9999","stock_state":4}}`
struct ShopObjectResponse<T: Decodable>: Decodable {
    let code: Int
    let msg: String?
    let data: T?
}

/// 商城库存查询结果。
///
/// 实测：`{"code":200,"data":{"stock":"9999","stock_state":4}}`
struct ShopStock: Decodable {
    /// 库存数。实测是**字符串**（`"9999"`），不是数字。
    let stock: String?
    /// 库存状态码。实测 `4` = 充足。
    let stockState: Int?

    enum CodingKeys: String, CodingKey {
        case stock
        case stockState = "stock_state"
    }

    /// 库存数的整数值（`stock` 是字符串，转不动就返回 nil）。
    var stockCount: Int? { Int(stock ?? "") }

    /// 是否售罄。
    ///
    /// ⚠️ 假设说明：实测只见过 `stock_state: 4`（充足）。
    /// 网页版 `item_ctrl.js` 的判定是 `stock_state <= 0` → 已售罄，本工程沿用。
    var isSoldOut: Bool { (stockState ?? 0) <= 0 }
}

/// 商城订单查询响应。
///
/// 实测：`{"code":200,"data":{"list":[...],"total":N}}`
struct ShopOrderQueryResponse: Decodable {
    let code: Int
    let msg: String?
    let data: ShopOrderPage?

    struct ShopOrderPage: Decodable {
        let list: [ShopOrder]?
        let total: Int?
    }
}

/// 商城发货内容（订单对应的卡密明文）。
///
/// 实测：`{"code":200,"data":{"secret":"...","leave_message":"...","delivery_files":[...]}}`
struct ShopOrderSecret: Decodable {
    let secret: String?
    let leaveMessage: String?
    let deliveryFiles: [ShopDeliveryFile]?

    enum CodingKeys: String, CodingKey {
        case secret
        case leaveMessage = "leave_message"
        case deliveryFiles = "delivery_files"
    }
}

/// 发货附件。
struct ShopDeliveryFile: Decodable, Hashable {
    let name: String?
    let url: String?
    let size: String?
}

// MARK: - 商城订单

/// 商城订单。
///
/// 字段与网页版订单查询页（`/user/index/query` → `assets/user/controller/index/query.js`
/// 的 `_CreateOrderItem`）**逐一对应**：
///
/// ```json
/// {
///   "trade_no": "20261025...", "create_time": "2026-10-25 12:00:00",
///   "pay_time": "2026-10-25 12:00:30", "status": 1, "delivery_status": 1,
///   "amount": "50.00", "card_num": 1, "password": false,
///   "race": "周卡", "sku": {...}, "secret": "LG-XXXX-XXXX",
///   "delivery_files": [...],
///   "pay": { "icon": "...", "name": "支付宝" },
///   "commodity": { "id": 3, "name": "LG 月卡", "cover": "...", "leave_message": "..." }
/// }
/// ```
///
/// ⚠️ 订单列表接口在**未登录时返回空数组**（实测 `data.list = []`），
/// 因此这些字段是从前端渲染逻辑反推的结构，而非实测响应。
/// 为了「字段名对不上时页面也不空白」，每个字段都做**宽松解析**：
/// 尝试多个候选键，取第一个命中的；都没有则显示「—」。
struct ShopOrder: Identifiable, Hashable, Decodable {

    /// 订单号。网页版显示为 `#<trade_no>`。
    let tradeNo: String
    /// 下单时间。
    let createTime: String
    /// 付款时间。
    let payTime: String?
    /// 订单状态：0 待付款 / 1 已付款。
    let status: Int
    /// 发货状态：0 等待发货 / 1 已发货。
    let deliveryStatus: Int
    /// 订单金额。
    let amount: String
    /// 购买数量。
    let cardNum: Int
    /// 是否需要查询密码才能看卡密。
    let needsPassword: Bool
    /// 商品类型（`race`）。
    let race: String?
    /// SKU 明细。
    let sku: [String: String]?
    /// 卡密明文（`password == false` 时直接显示）。
    let secret: String?
    /// 发货附件。
    let deliveryFiles: [ShopDeliveryFile]?
    /// 支付方式。
    let pay: ShopPayMethod?
    /// 商品快照。
    let commodity: ShopOrderCommodity?

    var id: String { tradeNo }

    // MARK: 宽松解析

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        // 宽松取值：逐个候选键尝试，取第一个能解出来的。
        //
        // ⚠️ 不要写 `if let v = try? c.decodeIfPresent(T.self, forKey: key), v != nil { return v! }`：
        // Swift 5 的 `try?` 会**扁平化**嵌套可选（SE-0230），`decodeIfPresent` 返回 `T?`
        // 经 `try?` 后仍是 `T?`，`if let` 解出的是**非可选** `T`，
        // 再写 `v!` 就报 "cannot force unwrap value of non-optional type 'T'"。
        func value<T: Decodable>(_ keys: [CodingKeys], default def: T) -> T {
            for key in keys {
                if let v = try? c.decode(T.self, forKey: key) {
                    return v
                }
            }
            return def
        }

        let tradeNo = value([.tradeNo, .tradeNoSnake, .orderNo, .orderNoSnake, .sn], default: "")
        self.tradeNo = tradeNo.isEmpty ? "—" : tradeNo

        self.createTime = value([.createTime, .createTimeSnake, .createdAt, .addTime], default: "—")
        self.payTime = try? c.decodeIfPresent(String.self, forKey: .payTime)
            ?? (try? c.decodeIfPresent(String.self, forKey: .payTimeSnake))
        self.status = value([.status], default: -1)
        self.deliveryStatus = value([.deliveryStatus, .deliveryStatusSnake], default: -1)
        self.amount = value([.amount, .price, .total], default: "—")
        self.cardNum = value([.cardNum, .cardNumSnake, .quantity, .num], default: 0)
        self.needsPassword = value([.password, .hasPassword], default: false)
        self.race = try? c.decodeIfPresent(String.self, forKey: .race)
        self.sku = try? c.decodeIfPresent([String: String].self, forKey: .sku)
        self.secret = try? c.decodeIfPresent(String.self, forKey: .secret)
        self.deliveryFiles = try? c.decodeIfPresent([ShopDeliveryFile].self, forKey: .deliveryFiles)
        self.pay = try? c.decodeIfPresent(ShopPayMethod.self, forKey: .pay)
        self.commodity = try? c.decodeIfPresent(ShopOrderCommodity.self, forKey: .commodity)
    }

    enum CodingKeys: String, CodingKey {
        case tradeNo = "trade_no"
        case tradeNoSnake = "tradeNo"
        case orderNo = "order_no"
        case orderNoSnake = "orderNo"
        case sn
        case createTime
        case createTimeSnake = "create_time"
        case createdAt = "created_at"
        case addTime = "add_time"
        case payTime
        case payTimeSnake = "pay_time"
        case status
        case deliveryStatus
        case deliveryStatusSnake = "delivery_status"
        case amount
        case price
        case total
        case cardNum
        case cardNumSnake = "card_num"
        case quantity
        case num
        case password
        case hasPassword = "has_password"
        case race
        case sku
        case secret
        case deliveryFiles = "delivery_files"
        case pay
        case commodity
    }

    // MARK: 网页版文案

    /// 订单状态文案。
    ///
    /// 网页版 `_GetStatusText`：
    /// `0 → 待付款`、`1 → 已付款`，其余 → `未知状态`。
    var statusTitle: String {
        switch status {
        case 0: return "待付款"
        case 1: return "已付款"
        default: return "未知状态"
        }
    }

    /// 发货状态文案。
    ///
    /// 网页版 `_GetShipmentStatusText`：
    /// `0 → 等待发货`、`1 → 已发货`，其余 → `等待发货`。
    var deliveryStatusTitle: String {
        switch deliveryStatus {
        case 0: return "等待发货"
        case 1: return "已发货"
        default: return "等待发货"
        }
    }

    /// 订单金额（带货币符号）。
    var amountText: String { "¥\(amount)" }
}

/// 支付方式。
struct ShopPayMethod: Decodable, Hashable {
    let icon: String?
    let name: String?
}

/// 订单里的商品快照。
struct ShopOrderCommodity: Decodable, Hashable {
    let id: Int?
    let name: String?
    let cover: String?
    /// 发货留言。
    let leaveMessage: String?
}

// MARK: - 商城商品（完整版）

/// 商城商品。
///
/// 实测（`GET /user/api/index/commodity`）：
/// ```json
/// { "id": 2, "name": "LG 周卡", "cover": "/favicon.ico", "status": 1,
///   "delivery_way": 0, "price": 14, "user_price": 14, "hide": 0,
///   "owner": null, "inventory_hidden": 0, "recommend": 0, "category_id": 2,
///   "stock": 9999, "tags": [], "seckill_status": 0, "order_sold": 1,
///   "category": { "id": 2, "name": "LG 授权", "icon": "/favicon.ico" },
///   "seckill_active": false, "has_wholesale": false, "stock_state": 4 }
/// ```
struct ShopCommodity: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let cover: String?
    let status: Int?
    /// 发货方式：`0` 自动发货，否则在线发货。
    let deliveryWay: Int?
    let price: Double
    let userPrice: Double?
    let hide: Int?
    let owner: Int?
    let inventoryHidden: Int?
    let recommend: Int?
    let categoryId: Int?
    let stock: Int?
    let tags: [String]?
    let seckillStatus: Int?
    let orderSold: Int?
    let category: ShopCategoryBrief?
    let seckillActive: Bool?
    let hasWholesale: Bool?
    let stockState: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, cover, status, price, hide, recommend, stock, tags
        case userPrice = "user_price"
        case deliveryWay = "delivery_way"
        case owner
        case inventoryHidden = "inventory_hidden"
        case categoryId = "category_id"
        case orderSold = "order_sold"
        case seckillStatus = "seckill_status"
        case seckillActive = "seckill_active"
        case hasWholesale = "has_wholesale"
        case stockState = "stock_state"
        case category
    }

    // MARK: 网页版渲染规则

    /// 发货方式文案。网页版：`delivery_way === 0` → 「自动发货」，否则「在线发货」。
    var deliveryWayTitle: String {
        deliveryWay == 0 ? "自动发货" : "在线发货"
    }

    /// 是否推荐。网页版：`recommend == 1` → 显示「推荐」标签。
    var isRecommended: Bool { recommend == 1 }

    /// 是否售罄。网页版商品卡片：`stock == 0` → 加 `soldout` 样式 + 「售罄」角标。
    var isSoldOut: Bool { (stock ?? 0) == 0 }

    /// 是否上架。网页版只展示上架且未隐藏的商品。
    var isOnSale: Bool { status == 1 && hide == 0 }

    /// 展示价格。网页版商品卡片用的是 **`price`**（不是 `user_price`）。
    var displayPrice: String {
        let value = price
        // 去掉多余的尾随零（网页版 format.amountRemoveTrailingZeros 的简化版）。
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        return String(format: "%.2f", value)
    }

    /// 价格带货币符号（网页版 `format.currencySymbol()` = `¥`）。
    var priceText: String { "¥\(displayPrice)" }

    /// 库存文案。网页版：「库存：N」。
    var stockText: String { "库存：\(stock ?? 0)" }

    /// 已售文案。网页版：「已售：N」。
    var orderSoldText: String { "已售：\(orderSold ?? 0)" }

    /// 虚拟商品声明（网页版固定文案）。
    static let disclaimerText = "该产品是虚拟产品，一经激活不予退款"
}

// MARK: - 商城分类（店铺）

/// 商品的简要分类信息（嵌套对象）。
///
/// 实测：`{"id": 2, "name": "LG 授权", "icon": "/favicon.ico"}`
struct ShopCategoryBrief: Hashable, Decodable {
    let id: Int
    let name: String
    let icon: String?
}

/// 商城分类 —— 网页版里的「店铺 / 商品分组」。
///
/// 实测（`GET /user/api/index/data`）：
/// ```json
/// { "id": 2, "name": "LG 授权", "sort": 2, "create_time": "2026-10-22 06:50:23",
///   "owner": 0, "icon": "/favicon.ico", "status": 1, "hide": 0,
///   "user_level_config": null, "pid": null, "commodity_count": 4 }
/// ```
struct ShopCategory: Identifiable, Hashable, Decodable {
    let id: Int
    let name: String
    let sort: Int?
    let createTime: String?
    /// 归属者 id（0 = 平台自营）。
    let owner: Int?
    let icon: String?
    let status: Int?
    let hide: Int?
    let userLevelConfig: String?
    let pid: Int?
    /// 该分类下的商品数。
    let commodityCount: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, sort, owner, icon, status, hide, pid
        case createTime = "create_time"
        case userLevelConfig = "user_level_config"
        case commodityCount = "commodity_count"
    }

    /// 是否启用。网页版只展示 `status == 1 && hide == 0` 的分类。
    var isActive: Bool { status == 1 && hide == 0 }

    /// 归属文案。
    ///
    /// ⚠️ 假设说明：`owner` 字段实测为 `0`，含义未在文档中定义。
    /// 按商城惯例，`0` 表示平台自营，非 0 表示商户 id。
    var ownerTitle: String {
        owner == 0 ? "平台自营" : "商户 #\(owner ?? 0)"
    }
}
