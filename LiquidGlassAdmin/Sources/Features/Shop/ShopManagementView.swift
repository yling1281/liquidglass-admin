import SwiftUI

// MARK: - 店铺管理

/// 店铺管理页。
///
/// 与网页版**商城前台（羁序工坊）**保持一致：
/// - **分类（店铺）**：横向切换条，网页版用 `CAT_ID` 切换。
/// - **商品卡片**：完全复刻网页版商品卡片的元素与文案 ——
///   标签（自动发货/在线发货、推荐）、标题、价格（`price` 而非 `user_price`）、
///   「库存：N」「已售：N」、虚拟商品声明、售罄角标。
/// - **订单查询**：网页版「订单查询」页的关键词搜索 + 订单卡片结构
///   （状态徽标、订单号、下单/付款时间、支付方式、金额、商品信息、宝贝内容）。
/// - **库存/价格**：点商品卡片可实时查库存与试算价格。
///
/// 数据全部来自商城前台公开接口（`siyecaogf.cn`），无需登录。
struct ShopManagementView: View {

    @ObservedObject var store: ShopStore

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selectedCommodity: ShopCommodity?
    @State private var secretRequest: SecretRequest?

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                categoryStrip
                commoditySection
                orderSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("店铺管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task {
                        await store.loadCategories()
                        await store.loadCommodities()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .refreshable {
            await store.loadCategories()
            await store.loadCommodities()
        }
        .task {
            await store.loadIfNeeded()
        }
        .overlay(alignment: .top) {
            ToastBanner(message: $store.toast, isError: true)
        }
        .sheet(item: $selectedCommodity) { commodity in
            CommodityDetailSheet(commodity: commodity, store: store)
        }
        .sheet(item: $secretRequest) { request in
            SecretSheet(request: request, store: store)
        }
    }

    // MARK: 分类（店铺）切换条

    @ViewBuilder
    private var categoryStrip: some View {
        if !store.categories.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("店铺 / 分类")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        categoryChip(
                            title: "全部",
                            count: store.commodities.count,
                            isSelected: store.selectedCategoryId == nil
                        ) {
                            store.selectedCategoryId = nil
                        }

                        ForEach(store.categories) { category in
                            categoryChip(
                                title: category.name,
                                count: category.commodityCount,
                                isSelected: store.selectedCategoryId == category.id
                            ) {
                                store.selectedCategoryId = category.id
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private func categoryChip(
        title: String,
        count: Int?,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                if let count {
                    Text("\(count)")
                        .font(.caption2)
                        .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
                }
            }
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                isSelected ? Color.accentColor : Color.secondary.opacity(0.12),
                in: Capsule()
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }

    // MARK: 商品

    private var commoditySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("商品")
                    .font(.headline)
                Spacer()
                if !store.commodities.isEmpty {
                    Text("\(store.commodities.count) 个")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            switch store.commodityState {
            case .loading where store.commodities.isEmpty:
                StateView.loading("正在加载商品…")
                    .frame(height: 200)
            case .failed(let error) where store.commodities.isEmpty:
                StateView.failure(error) {
                    Task { await store.loadCommodities() }
                }
                .frame(height: 240)
            case .loaded(let list) where list.isEmpty:
                StateView.empty("没有商品")
                    .frame(height: 200)
            default:
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 200, maximum: 340), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(store.commodities) { commodity in
                        CommodityCard(commodity: commodity) {
                            selectedCommodity = commodity
                        }
                    }
                }
            }
        }
    }

    // MARK: 订单

    private var orderSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("订单")
                    .font(.headline)
                Spacer()
                if store.orderTotal > 0 {
                    Text("共 \(store.orderTotal) 条")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // 网页版订单查询：关键词为「联系方式或订单号」
            HStack(spacing: 8) {
                TextField("联系方式或订单号", text: $store.orderKeyword)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .onSubmit { Task { await store.queryOrders(keyword: store.orderKeyword) } }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                Button {
                    Task { await store.queryOrders(keyword: store.orderKeyword) }
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("查询订单")
            }

            switch store.orderState {
            case .idle:
                Text("输入联系方式或订单号查询订单。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            case .loading:
                StateView.loading("正在查询…")
                    .frame(height: 160)
            case .failed(let error):
                StateView.failure(error) {
                    Task { await store.queryOrders(keyword: store.orderKeyword) }
                }
                .frame(height: 200)
            case .loaded(let orders):
                if orders.isEmpty {
                    // 网页版：无结果显示「没有查询到相关订单」
                    Text("没有查询到相关订单")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(spacing: 10) {
                        ForEach(orders) { order in
                            OrderCard(order: order) {
                                secretRequest = SecretRequest(order: order)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - 商品卡片

/// 商品卡片 —— 复刻网页版商品卡片。
///
/// 元素与文案严格对齐 `assets/user/controller/index/index.js` 的 `_PushCommodityList`。
struct CommodityCard: View {
    let commodity: ShopCommodity
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 标签区：发货方式 + 推荐
            HStack(spacing: 6) {
                Text(commodity.deliveryWayTitle)
                    .font(.caption2)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.green.opacity(0.16), in: Capsule())
                    .foregroundStyle(.green)

                if commodity.isRecommended {
                    Text("推荐")
                        .font(.caption2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.16), in: Capsule())
                        .foregroundStyle(.blue)
                }

                Spacer()

                if commodity.isSoldOut {
                    Text("售罄")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(.red.opacity(0.16), in: Capsule())
                        .foregroundStyle(.red)
                }
            }

            Text(commodity.name)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)

            // 价格 —— 网页版用的是 price，不是 user_price
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.caption)
                    .foregroundStyle(.red)
                Text(commodity.displayPrice)
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.red)
            }

            HStack {
                Text(commodity.stockText)
                Spacer()
                Text(commodity.orderSoldText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            // 固定声明文案
            Text(ShopCommodity.disclaimerText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - 商品详情

/// 商品详情弹窗 —— 对应网页版 `/item/{id}` 页面。
///
/// 展示商品的完整信息，并提供**实时库存查询**与**价格试算**（网页版同款接口）。
struct CommodityDetailSheet: View {

    let commodity: ShopCommodity
    @ObservedObject var store: ShopStore

    @Environment(\.dismiss) private var dismiss
    @State private var stock: ShopStock?
    @State private var valuation: Double?
    @State private var quantity: Int = 1
    @State private var isQuerying = false

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                stockSection
                priceSection
            }
            .navigationTitle(commodity.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .task {
                await refresh()
            }
        }
    }

    private var basicSection: some View {
        Section("商品信息") {
            LabeledContent("商品 ID", value: "\(commodity.id)")
            LabeledContent("分类", value: commodity.category?.name ?? "—")
            LabeledContent("发货方式", value: commodity.deliveryWayTitle)
            LabeledContent("价格", value: commodity.priceText)
            LabeledContent("库存", value: "\(commodity.stock ?? 0)")
            LabeledContent("已售", value: "\(commodity.orderSold ?? 0)")
            if commodity.isRecommended {
                LabeledContent("标记", value: "推荐")
            }
        }
        .font(.subheadline)
    }

    private var stockSection: some View {
        Section {
            HStack {
                Text("实时库存")
                Spacer()
                if isQuerying {
                    ProgressView().controlSize(.small)
                } else {
                    Text(stock.map { "库存：\($0.stock ?? "—")" } ?? "—")
                        .font(.body.monospacedDigit())
                }
            }
            if let stock {
                HStack {
                    Text("库存状态")
                    Spacer()
                    Text(stock.isSoldOut ? "已售罄" : "充足")
                        .foregroundStyle(stock.isSoldOut ? .red : .green)
                }
            }
        } header: {
            Text("库存查询")
        } footer: {
            Text("实时调用 `POST /user/api/index/stock`，与网页版商品详情页同一接口。")
        }
    }

    private var priceSection: some View {
        Section {
            HStack {
                Text("购买数量")
                Spacer()
                Stepper(value: $quantity, in: 1...99) {
                    Text("\(quantity)")
                        .font(.body.monospacedDigit())
                }
                .labelsHidden()
                Text("\(quantity)")
                    .font(.body.monospacedDigit())
                    .frame(width: 34, alignment: .trailing)
            }

            HStack {
                Text("试算价格")
                Spacer()
                if let valuation {
                    Text("¥\(String(format: "%.2f", valuation))")
                        .font(.body.monospacedDigit().weight(.semibold))
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("价格试算")
        } footer: {
            Text("实时调用 `POST /user/api/index/valuation`，与网页版商品详情页同一接口。")
        }
    }

    private func refresh() async {
        isQuerying = true
        async let stockTask = store.queryStock(for: commodity)
        async let priceTask = store.queryValuation(itemId: commodity.id, quantity: quantity)
        stock = await stockTask
        valuation = await priceTask
        isQuerying = false
    }
}

// MARK: - 订单卡片

/// 订单卡片 —— 复刻网页版订单项。
///
/// 结构对齐 `assets/user/controller/index/query.js` 的 `_CreateOrderItem`：
/// 状态徽标 → 订单号 / 下单时间 / 付款时间 / 支付方式 → 订单金额
/// → 商品信息（缩略图、名称、SKU、数量）→ 宝贝内容（发货状态 + 卡密）。
struct OrderCard: View {
    let order: ShopOrder
    let onViewSecret: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        StatusBadge(title: order.statusTitle, color: order.statusColor)
                        if order.status == 1 {
                            StatusBadge(title: order.deliveryStatusTitle, color: .blue)
                        }
                    }
                    Text("#\(order.tradeNo)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Text("下单时间：\(order.createTime)")
                        if let payTime = order.payTime, !payTime.isEmpty, payTime != "-" {
                            Text("付款时间：\(payTime)")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    if let pay = order.pay {
                        HStack(spacing: 4) {
                            Text("支付方式：")
                            if let name = pay.name { Text(name) }
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("订单金额")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(order.amountText)
                        .font(.headline.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.red)
                }
            }

            Divider()

            // 商品信息
            HStack(spacing: 10) {
                if let cover = order.commodity?.cover, !cover.isEmpty {
                    AsyncImage(url: URL(string: cover)) { image in
                        image.resizable().aspectRatio(contentMode: .fill)
                    } placeholder: {
                        Color.secondary.opacity(0.15)
                    }
                    .frame(width: 44, height: 44)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(order.commodity?.name ?? "—")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 6) {
                        if let race = order.race, !race.isEmpty {
                            tag("商品类型: \(race)", color: .green)
                        }
                        if let sku = order.sku {
                            ForEach(sku.keys.sorted(), id: \.self) { key in
                                tag("\(key): \(sku[key] ?? "")", color: .blue)
                            }
                        }
                        tag("数量: \(order.cardNum)", color: .orange)
                    }
                }
                Spacer()
            }

            // 宝贝内容
            if order.status == 1 {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("宝贝内容", systemImage: "gift")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        Text(order.deliveryStatusTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if order.needsPassword {
                        Button(action: onViewSecret) {
                            Label("查看卡密", systemImage: "eye")
                                .font(.footnote)
                        }
                        .buttonStyle(.bordered)
                    } else if let secret = order.secret, !secret.isEmpty {
                        Text(secret)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let leaveMessage = order.commodity?.leaveMessage, !leaveMessage.isEmpty {
                        Text(leaveMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

// MARK: - 订单状态色

extension ShopOrder {
    /// 状态徽标颜色。网页版 class：`0 → pending`、`1 → paid`。
    var statusColor: Color {
        switch status {
        case 0: return .orange
        case 1: return .green
        default: return .secondary
        }
    }
}

// MARK: - 查看卡密

/// 「查看卡密」的请求上下文。
struct SecretRequest: Identifiable {
    let id = UUID()
    let order: ShopOrder
}

/// 输入查询密码以查看卡密。
///
/// 对应网页版：点「查看卡密」→ 弹密码框 → `POST /user/api/index/secret`。
struct SecretSheet: View {

    let request: SecretRequest
    @ObservedObject var store: ShopStore

    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var result: ShopOrderSecret?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("请输入查询密码", text: $password)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit { fetch() }
                } header: {
                    Text("订单 #\(request.order.tradeNo)")
                } footer: {
                    Text("网页版同样需要输入查询密码才能查看卡密内容。")
                }

                if let result {
                    Section("卡密内容") {
                        if let secret = result.secret, !secret.isEmpty {
                            Text(secret)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        }
                        if let leaveMessage = result.leaveMessage, !leaveMessage.isEmpty {
                            Text(leaveMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let files = result.deliveryFiles, !files.isEmpty {
                            ForEach(files, id: \.self) { file in
                                if let url = file.url, let link = URL(string: url) {
                                    Link(file.name ?? "附件", destination: link)
                                } else {
                                    Text(file.name ?? "附件")
                                }
                            }
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("查看卡密")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isLoading ? "查询中…" : "查询") {
                        fetch()
                    }
                    .disabled(password.isEmpty || isLoading)
                }
            }
        }
        .onAppear { focused = true }
    }

    @FocusState private var focused: Bool

    private func fetch() {
        guard !password.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil

        Task {
            switch await store.fetchSecret(tradeNo: request.order.tradeNo, password: password) {
            case .success(let secret):
                result = secret
            case .failure(let error):
                errorMessage = error.errorDescription
            }
            isLoading = false
        }
    }
}
