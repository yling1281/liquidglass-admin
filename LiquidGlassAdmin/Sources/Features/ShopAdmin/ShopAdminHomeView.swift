import SwiftUI

// MARK: - 店铺后台首页

/// 店铺后台的模块入口。
///
/// 布局与网页版侧边栏一致：按 MAIN / USER / TRADE / SHARED / CONFIG 分组，
/// 顺序、标题、图标全部对齐。iPhone 上是单个列表，iPad 上双列网格。
struct ShopAdminHomeView: View {

    @ObservedObject var client: ShopAdminSession

    @StateObject private var dashboard = ShopAdminDashboardStore()
    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        List {
            dashboardSection
            ForEach(ShopAdminModule.Group.allCases) { group in
                let modules = ShopAdminModule.modules(in: group)
                if !modules.isEmpty {
                    Section {
                        if isRegular {
                            grid(for: modules)
                        } else {
                            rows(for: modules)
                        }
                    } header: {
                        HStack(spacing: 6) {
                            Text(group.title)
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tertiary)
                            Text(group.localizedTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("店铺后台")
        .refreshable {
            await dashboard.load()
            await client.refresh()
        }
        .task {
            if case .idle = dashboard.state { await dashboard.load() }
        }
    }

    // MARK: 控制台指标

    @ViewBuilder
    private var dashboardSection: some View {
        Section {
            switch dashboard.state {
            case .loading, .idle:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在加载经营数据…")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            case .failed(let error):
                VStack(alignment: .leading, spacing: 8) {
                    Label(error.errorDescription ?? "加载失败",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    Button("重试") {
                        Task { await dashboard.load() }
                    }
                    .font(.footnote)
                }
            case .loaded:
                if dashboard.metrics.isEmpty {
                    Text("暂无经营数据")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                       count: isRegular ? 4 : 2),
                        spacing: 10
                    ) {
                        ForEach(dashboard.metrics) { metric in
                            metricTile(metric)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text("控制台")
        }
    }

    private func metricTile(_ metric: ShopMetric) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: metric.icon)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                Text(metric.title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(metric.value)
                .font(.headline.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 模块入口

    private func rows(for modules: [ShopAdminModule]) -> some View {
        ForEach(modules) { module in
            NavigationLink {
                ShopAdminListView(module: module)
            } label: {
                Label(module.title, systemImage: module.icon)
            }
        }
    }

    private func grid(for modules: [ShopAdminModule]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
            spacing: 12
        ) {
            ForEach(modules) { module in
                NavigationLink {
                    ShopAdminListView(module: module)
                } label: {
                    VStack(spacing: 8) {
                        Image(systemName: module.icon)
                            .font(.title3)
                            .foregroundStyle(.tint)
                        Text(module.title)
                            .font(.footnote)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 通用列表页

/// 一个模块的列表。
///
/// 字段渲染完全由 `ShopAdminField` 驱动：优先展示 id / 订单号 / 名称 /
/// 金额 / 状态 / 时间这几类，其余字段收进详情。
struct ShopAdminListView: View {

    @StateObject private var store: ShopAdminListStore
    @State private var selected: ShopItem?

    init(module: ShopAdminModule) {
        _store = StateObject(wrappedValue: ShopAdminListStore(module: module))
    }

    var body: some View {
        Group {
            if store.module.listPath == nil {
                ContentUnavailableView(
                    "\(store.module.title) 是表单型页面",
                    systemImage: store.module.icon,
                    description: Text("这个模块在网页版里是配置表单，请在浏览器里修改。")
                )
            } else {
                content
            }
        }
        .navigationTitle(store.module.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !store.module.title.isEmpty {
                    Text("共 \(store.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task {
            if case .idle = store.state { await store.load() }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.state {
        case .idle, .loading:
            ProgressView("正在加载\(store.module.title)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let error):
            ContentUnavailableView {
                Label("加载失败", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error.errorDescription ?? "未知错误")
            } actions: {
                Button("重试") {
                    Task { await store.load() }
                }
            }
        case .loaded(let count):
            if count == 0 && store.items.isEmpty {
                ContentUnavailableView(
                    "暂无数据",
                    systemImage: store.module.icon,
                    description: Text(store.keyword.isEmpty
                                      ? "这个模块还没有记录"
                                      : "没有匹配「\(store.keyword)」的记录")
                )
            } else {
                list
            }
        }
    }

    private var list: some View {
        List {
            ForEach(store.items) { item in
                Button {
                    selected = item
                } label: {
                    row(item)
                }
                .buttonStyle(.plain)
                .task {
                    await store.loadMoreIfNeeded(currentItem: item)
                }
            }

            if store.hasMore {
                HStack {
                    Spacer()
                    if store.isLoadingMore {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("已显示 \(store.items.count) / \(store.total)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .refreshable { await store.load() }
        .searchable(text: $store.keyword,
                    placement: .navigationBarDrawer(displayMode: .automatic),
                    prompt: searchPrompt)
        .onSubmit(of: .search) {
            Task { await store.load() }
        }
        .onChange(of: store.keyword) { _, newValue in
            if newValue.isEmpty {
                Task { await store.load() }
            }
        }
        .sheet(item: $selected) { item in
            ShopItemDetailSheet(module: store.module, item: item)
        }
    }

    private var searchPrompt: String {
        switch store.module.searchKey {
        case "keywords": return "搜索关键词"
        case "trade_no": return "订单号"
        case "secret": return "卡密内容"
        case "code": return "优惠码"
        default: return "该模块不支持搜索"
        }
    }

    private func row(_ item: ShopItem) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            // 标题行：名称 / 订单号 / 卡号
            HStack(spacing: 6) {
                Text(primaryTitle(item))
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 6)
                if let badge = statusBadge(item) {
                    Text(badge.text)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.color.opacity(0.15),
                                    in: Capsule())
                        .foregroundStyle(badge.color)
                }
            }

            // 字段行
            ForEach(ShopAdminField.displayKeys(for: item.raw).filter { $0 != primaryTitleKey(item) },
                    id: \.self) { key in
                HStack(alignment: .top, spacing: 8) {
                    Text(ShopAdminField.label(for: key))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: 62, alignment: .leading)
                    Text(ShopAdminField.text(item.raw[key]))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
    }

    private func primaryTitleKey(_ item: ShopItem) -> String {
        for key in ["name", "title", "trade_no", "order_no", "card_no", "email", "username", "code", "id"] {
            if let value = item.raw[key], !ShopAdminField.isBlank(value) {
                return key
            }
        }
        return "id"
    }

    private func primaryTitle(_ item: ShopItem) -> String {
        ShopAdminField.text(item.raw[primaryTitleKey(item)])
    }

    /// 状态徽标。
    ///
    /// 各模块的 `status` 含义不同（商品是上下架、订单是支付状态），
    /// 所以只在**语义明确**的模块上做映射；其余原样显示数字，
    /// 避免给出错误结论。
    private func statusBadge(_ item: ShopItem) -> (text: String, color: Color)? {
        guard let raw = item.raw["status"] else { return nil }
        let value = ShopAdminField.text(raw)
        let green = Color.green
        let orange = Color.orange
        let gray = Color.secondary

        switch store.module.api {
        case "commodity", "category":
            return value == "1" ? ("上架", green) : ("下架", gray)
        case "order", "rechargeOrder":
            switch value {
            case "0": return ("待支付", orange)
            case "1": return ("已支付", green)
            case "2": return ("已完成", green)
            default: return (value, gray)
            }
        case "card":
            switch value {
            case "0": return ("未售", green)
            case "1": return ("已售", gray)
            default: return (value, gray)
            }
        case "user", "manage":
            return value == "1" ? ("正常", green) : ("禁用", gray)
        default:
            return (value, gray)
        }
    }
}

// MARK: - 详情

/// 一条记录的全部字段。
///
/// 列表只展示 5 个摘要字段，其余（40+ 个）在这里按接口原顺序列出，
/// 并且**不隐藏任何字段** —— 排查问题时需要看原始值。
struct ShopItemDetailSheet: View {

    let module: ShopAdminModule
    let item: ShopItem

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("字段") {
                    ForEach(orderedKeys, id: \.self) { key in
                        HStack(alignment: .top, spacing: 10) {
                            Text(ShopAdminField.label(for: key))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 96, alignment: .leading)
                            Text(ShopAdminField.text(item.raw[key]))
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                            Spacer(minLength: 0)
                        }
                    }
                }

                Section {
                    Text("原始键名：\(keySummary)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("\(module.title) · 详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private var orderedKeys: [String] {
        let all = Array(item.raw.keys)
        // 先按偏好顺序，再补剩下的（保持接口原顺序更利于对照网页版）
        let preferred = ShopAdminField.preferredOrder.filter { all.contains($0) }
        let rest = all.filter { !preferred.contains($0) }.sorted()
        return preferred + rest
    }

    private var keySummary: String {
        "\(item.raw.keys.count) 个字段"
    }
}
