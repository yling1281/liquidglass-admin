import Foundation

// MARK: - 店铺后台的模块清单

/// 店铺后台（acg-faka）的侧边栏模块。
///
/// 依据是线上后台的真实菜单分组（MAIN / USER / TRADE / SHARED / CONFIG）
/// 和 `app/Controller/Admin/Api/` 下的控制器，两者一一对应。
///
/// 设计上刻意做成**数据驱动**：23 个模块的列表接口都是
/// `GET /admin/api/{module}/data`，响应都是 `{code, data:{list, total}}`，
/// 所以只需要一份「模块配置 + 通用列表页」就能全部覆盖，
/// 不必为每个模块手写一遍页面。
struct ShopAdminModule: Identifiable, Hashable {

    /// 接口里的模块名（也用作 `/admin/api/{api}/data` 的一段）。
    let api: String
    /// 菜单标题（与网页版一致）。
    let title: String
    /// SF Symbol。
    let icon: String
    /// 所属分组。
    let group: Group
    /// 列表接口路径；`nil` 表示这个模块是表单型页面（设置类），没有列表。
    let listPath: String?
    /// 该模块特有的搜索参数名；`nil` 表示不支持关键词搜索。
    let searchKey: String?

    var id: String { api }

    enum Group: String, CaseIterable, Identifiable {
        case main
        case user
        case trade
        case shared
        case config

        var id: String { rawValue }

        /// 与网页版侧边栏的分组标题一致。
        var title: String {
            switch self {
            case .main: return "MAIN"
            case .user: return "USER"
            case .trade: return "TRADE"
            case .shared: return "SHARED"
            case .config: return "CONFIG"
            }
        }

        var localizedTitle: String {
            switch self {
            case .main: return "概览"
            case .user: return "用户与资金"
            case .trade: return "交易"
            case .shared: return "共享"
            case .config: return "配置"
            }
        }
    }

    /// 建一个列表型模块。
    private static func list(
        _ api: String,
        _ title: String,
        _ icon: String,
        _ group: Group,
        searchKey: String? = nil
    ) -> ShopAdminModule {
        ShopAdminModule(
            api: api,
            title: title,
            icon: icon,
            group: group,
            listPath: "/admin/api/\(api)/data",
            searchKey: searchKey
        )
    }

    /// 全部模块 —— 顺序与网页版侧边栏一致。
    static let all: [ShopAdminModule] = [
        // MAIN
        ShopAdminModule(api: "dashboard", title: "控制台", icon: "square.grid.2x2",
                        group: .main, listPath: "/admin/api/dashboard/data", searchKey: nil),

        // USER
        list("user", "会员管理", "person.2", .user, searchKey: "keywords"),
        list("ticket", "工单管理", "text.bubble", .user, searchKey: "keywords"),
        list("message", "消息管理", "envelope", .user),
        list("rechargeOrder", "充值订单", "creditcard", .user, searchKey: "trade_no"),
        list("bill", "账单管理", "doc.text", .user),
        list("group", "会员等级", "rosette", .user),
        list("businessLevel", "商户等级", "building.2", .user),
        list("cash", "提现管理", "banknote", .user),

        // TRADE
        list("category", "分类管理", "square.stack.3d.up", .trade),
        list("commodity", "商品管理", "shippingbox", .trade, searchKey: "keywords"),
        list("card", "卡密管理", "key", .trade, searchKey: "secret"),
        list("coupon", "优惠券", "ticket", .trade, searchKey: "code"),
        list("order", "商品订单", "cart", .trade, searchKey: "trade_no"),

        // SHARED
        list("store", "店铺共享", "point.3.connected.trianglepath.dotted", .shared),
        list("priceTemplate", "加价模板", "square.and.pencil", .shared),

        // CONFIG
        list("config", "网站设置", "gearshape", .config),
        list("manage", "管理员", "person.badge.key", .config),
        list("plugin", "通用插件", "puzzlepiece", .config),
        list("pay", "支付管理", "wallet.pass", .config),
        list("file", "文件管理", "folder", .config),
        list("lang", "语言翻译", "character.bubble", .config),
        list("log", "操作日志", "clock.arrow.circlepath", .config)
    ]

    static func modules(in group: Group) -> [ShopAdminModule] {
        all.filter { $0.group == group }
    }
}

// MARK: - 字段标题

/// 把接口字段名翻成中文列标题。
///
/// acg-faka 的字段是 snake_case 且量很大（一个商品有 40+ 字段），
/// 逐个手写不现实。这里用一张常用字段表覆盖绝大多数，查不到时
/// 按驼峰/下划线拆词后原样展示 —— 宁可显示英文，也不假装知道含义。
enum ShopAdminField {

    /// 优先展示的字段顺序（列表页只显示这几个，其余进详情页）。
    static let preferredOrder: [String] = [
        "id", "trade_no", "order_no", "card_no", "secret", "name", "title",
        "email", "username", "nickname", "category_id", "user_id",
        "price", "user_price", "amount", "money", "total_price",
        "stock", "status", "quantity", "num",
        "create_time", "update_time", "pay_time", "expire_time", "login_time"
    ]

    private static let labels: [String: String] = [
        "id": "ID",
        "trade_no": "订单号",
        "order_no": "订单号",
        "card_no": "卡密编号",
        "secret": "卡密",
        "name": "名称",
        "title": "标题",
        "description": "描述",
        "email": "邮箱",
        "username": "用户名",
        "nickname": "昵称",
        "category_id": "分类 ID",
        "category": "分类",
        "user_id": "会员 ID",
        "user": "会员",
        "price": "价格",
        "user_price": "售价",
        "factory_price": "成本价",
        "amount": "金额",
        "money": "金额",
        "total_price": "合计",
        "stock": "库存",
        "order_sold": "已售",
        "status": "状态",
        "quantity": "数量",
        "num": "数量",
        "create_time": "创建时间",
        "update_time": "更新时间",
        "pay_time": "支付时间",
        "expire_time": "到期时间",
        "login_time": "登录时间",
        "last_login_time": "最后登录",
        "login_ip": "登录 IP",
        "cover": "封面",
        "sort": "排序",
        "remark": "备注",
        "note": "备注",
        "code": "编码",
        "type": "类型",
        "delivery_way": "发货方式",
        "balance": "余额",
        "coin": "积分",
        "avatar": "头像",
        "content": "内容",
        "reply": "回复",
        "ip": "IP",
        "action": "操作",
        "path": "路径",
        "method": "方法",
        "discount": "折扣",
        "is_boss": "超级管理员",
        "google_secret": "谷歌验证",
        "category_name": "分类名",
        "commodity_name": "商品名",
        "user_name": "会员名",
        "pay_name": "支付方式",
        "settlement": "结算状态",
        "recharge_amount": "充值金额",
        "turnover": "营业额"
    ]

    static func label(for key: String) -> String {
        if let known = labels[key] {
            return known
        }
        // 兜底：snake_case → "Snake Case"
        return key
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    /// 哪些字段不适合直接列在卡片上（太长或纯内部字段）。
    static let hidden: Set<String> = [
        "password", "salt", "google_secret", "security_password",
        "description", "content", "cover", "avatar", "delivery_message",
        "delivery_auto", "delivery_auto_mode", "contact_type",
        "coupon", "shared_id", "shared_code", "shared_premium",
        "shared_stock", "shared_premium_type", "shared_premium_template",
        "seckill_status", "api_status", "password_status", "sort", "owner"
    ]

    /// 给列表卡片挑 4~6 个最有信息量的字段。
    static func displayKeys(for item: [String: Any]) -> [String] {
        var picked: [String] = []
        for key in preferredOrder {
            guard let value = item[key], !ShopAdminField.isBlank(value) else { continue }
            if hidden.contains(key) { continue }
            picked.append(key)
            if picked.count >= 5 { break }
        }
        // 兜底：如果偏好字段一个都没命中，就取前 4 个非空字段
        if picked.isEmpty {
            picked = item.keys
                .filter { !hidden.contains($0) }
                .filter { !isBlank(item[$0] as Any) }
                .sorted()
                .prefix(4)
                .map { $0 }
        }
        return picked
    }

    static func isBlank(_ value: Any) -> Bool {
        if value is NSNull { return true }
        if let text = value as? String {
            return text.isEmpty || text == "null"
        }
        return false
    }

    /// 把任意值转成可展示的字符串。
    static func text(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "—" }
        if let text = value as? String {
            return text.isEmpty ? "—" : text
        }
        if let number = value as? NSNumber {
            // 布尔值显示成「是/否」，比 1/0 好读
            let type = String(cString: number.objCType)
            if type == "c" || type == "B" {
                return number.boolValue ? "是" : "否"
            }
            // 金额类字段后端常返回字符串，这里只处理真数字
            if number.doubleValue == number.doubleValue.rounded(),
               abs(number.doubleValue) < 1e15 {
                return String(number.int64Value)
            }
            return number.stringValue
        }
        return "\(value)"
    }
}
