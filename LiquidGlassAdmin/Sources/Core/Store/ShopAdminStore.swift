import Foundation

// MARK: - 列表项

/// 店铺后台列表里的一行。
///
/// 各模块字段差异很大（商品 40+ 字段、日志 8 个字段），
/// 所以不做强类型模型，直接包一层 `[String: Any]`，
/// 由 `ShopAdminField` 决定怎么展示。
struct ShopItem: Identifiable, Hashable {

    let id: String
    let raw: [String: Any]

    init(raw: [String: Any], fallbackIndex: Int) {
        self.raw = raw
        // 优先用 id，其次订单号/卡号，最后退化成序号
        for key in ["id", "trade_no", "order_no", "card_no", "code", "name"] {
            if let value = raw[key], !ShopAdminField.isBlank(value) {
                self.id = "\(key)-\(ShopAdminField.text(value))-\(fallbackIndex)"
                return
            }
        }
        self.id = "row-\(fallbackIndex)"
    }

    static func == (lhs: ShopItem, rhs: ShopItem) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

// MARK: - 通用列表 Store

/// 一个模块的列表状态。
///
/// 23 个模块共用它：模块差异全部由 `ShopAdminModule` 的配置描述，
/// 请求走 `ShopAdminClient.list`，渲染走 `ShopAdminField` 的字段表。
@MainActor
final class ShopAdminListStore: ObservableObject {

    let module: ShopAdminModule

    @Published private(set) var items: [ShopItem] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var state: LoadState<Int> = .idle
    @Published var keyword: String = ""
    @Published private(set) var isLoadingMore = false

    private var page = 1
    private let pageSize = 30

    init(module: ShopAdminModule) {
        self.module = module
    }

    /// 是否还有下一页。
    var hasMore: Bool { items.count < total }

    /// 首次加载 / 下拉刷新。
    func load(reset: Bool = true) async {
        guard let path = module.listPath else {
            state = .loaded(0)
            return
        }
        if reset {
            page = 1
            state = .loading
        }

        var query: [String: String] = [
            "page": String(page),
            "limit": String(pageSize)
        ]
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        if let searchKey = module.searchKey, !trimmed.isEmpty {
            query[searchKey] = trimmed
        }

        do {
            let result = try await ShopAdminClient.shared.list(path: path, query: query,
                                                               refererPage: refererPage)
            let mapped = result.items.enumerated().map { index, raw in
                ShopItem(raw: raw, fallbackIndex: (page - 1) * pageSize + index)
            }
            if reset {
                items = mapped
            } else {
                items.append(contentsOf: mapped)
            }
            total = result.total
            state = .loaded(total)
        } catch let error as ShopAdminClient.ShopAdminError {
            state = .failed(.transport(error.errorDescription ?? "加载失败"))
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
        isLoadingMore = false
    }

    /// 滚动到底部时加载下一页。
    func loadMoreIfNeeded(currentItem: ShopItem) async {
        guard hasMore, !isLoadingMore, state.value != nil else { return }
        guard items.last?.id == currentItem.id else { return }
        isLoadingMore = true
        page += 1
        await load(reset: false)
    }

    /// 该模块对应的「页面地址」，用作 Referer（必须与站点同域）。
    private var refererPage: String {
        "/admin/\(module.api)/index"
    }
}

// MARK: - 控制台

/// 控制台的一个指标。
///
/// 用结构体而不是元组：`ForEach(..., id: \.title)` 需要 keypath，
/// 而 Swift 的元组没有 keypath —— 用元组会直接编译不过。
struct ShopMetric: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let icon: String
}

/// 控制台（Dashboard）的统计。
///
/// 接口 `GET /admin/api/dashboard/data` 返回一堆经营指标，
/// 这里只取网页版首页真正展示的那些。
@MainActor
final class ShopAdminDashboardStore: ObservableObject {

    @Published private(set) var metrics: [ShopMetric] = []
    @Published private(set) var state: LoadState<Int> = .idle

    /// 网页版控制台的指标顺序与文案。
    private static let fields: [(key: String, title: String, icon: String, money: Bool)] = [
        ("turnover", "营业额", "chart.line.uptrend.xyaxis", true),
        ("order_num", "订单数", "cart", false),
        ("user_register_num", "新注册会员", "person.badge.plus", false),
        ("buyer_num", "下单人数", "person.2", false),
        ("profit", "利润", "chart.pie", true),
        ("cost", "成本", "tray", true),
        ("unpaid_order_num", "未支付订单", "clock.badge.exclamationmark", false),
        ("recharge_num", "充值笔数", "creditcard", false),
        ("recharge_amount", "充值金额", "banknote", true),
        ("cash_money_status_1", "待结算提现", "hourglass", true)
    ]

    func load() async {
        state = .loading
        do {
            let payload = try await ShopAdminClient.shared.request(
                path: "/admin/api/dashboard/data",
                refererPage: "/admin/dashboard/index"
            )
            guard let dict = payload as? [String: Any] else {
                metrics = []
                state = .loaded(0)
                return
            }
            metrics = Self.fields.compactMap { field in
                guard let raw = dict[field.key], !ShopAdminField.isBlank(raw) else { return nil }
                let text = ShopAdminField.text(raw)
                return ShopMetric(
                    id: field.key,
                    title: field.title,
                    value: field.money ? "¥" + text : text,
                    icon: field.icon
                )
            }
            state = .loaded(metrics.count)
        } catch let error as ShopAdminClient.ShopAdminError {
            state = .failed(.transport(error.errorDescription ?? "加载失败"))
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }
}
