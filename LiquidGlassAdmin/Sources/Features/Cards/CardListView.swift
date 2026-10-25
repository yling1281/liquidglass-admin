import SwiftUI

// MARK: - 卡密列表页

/// 卡密列表页。
///
/// **与网页版卡密中心（`/card/key`）完全一致**：
///
/// | 网页版 | 本工程 |
/// |---|---|
/// | 搜索框 label「卡密/批次」 | 同文案，placeholder「输入编号或批次」 |
/// | 状态筛选：全部/未发放/已发放/已使用/已冻结/已作废/已过期 | 同枚举同顺序 |
/// | 表格列：卡密编号 · 商品 · 状态 · 渠道 · 到期 · 订单号 | 同列同顺序 |
/// | 状态列用 tag 着色 | 同色系映射 |
/// | 批量：冻结/封禁（填原因）· 解冻 · 解封 · 删除 | 同动作同接口 |
/// | 确认文案「确认解冻选中的 N 张卡？」等 | 同文案 |
/// | 提示「成功 N 条，跳过 M 条」 | 同文案 |
/// | 生成表单：批次名 · 商品 · 数量 · 有效天数 | 同字段同默认值 |
///
/// **布局差异**（响应式要求，非功能差异）：
/// - iPhone：单列 `List`，点行进详情页。
/// - iPad：分栏 —— 左侧列表 + 右侧详情；可切「网格 / 列表」，
///   列表模式下是**多列对齐的表格**（复刻网页版表格），网格模式是多列卡片。
struct CardListView: View {

    @ObservedObject var store: CardListStore
    @ObservedObject var session: SessionStore

    let isRegular: Bool

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var selectedCard: CardKey?
    @State private var isGridMode = false
    @State private var statusAction: StatusActionTarget?
    @State private var confirmAction: ConfirmAction?
    /// 多选模式：长按任一张卡进入，点「完成」或全不选时退出。
    @State private var isSelecting = false
    /// 触觉反馈的触发器（每次进出多选 +1）。
    @State private var selectTick = 0

    /// 需要填原因的批量操作。
    private struct StatusActionTarget: Identifiable {
        let id = UUID()
        let status: CardStatus
        let title: String
    }

    /// 需要二次确认的批量操作（文案与网页版一致）。
    private enum ConfirmAction: Identifiable, Equatable {
        case unfreeze, unban, delete

        var id: String {
            switch self {
            case .unfreeze: return "unfreeze"
            case .unban: return "unban"
            case .delete: return "delete"
            }
        }

        /// 确认框正文 —— 逐字对齐网页版。
        var message: String {
            switch self {
            case .unfreeze: return "确认解冻选中的"
            case .unban: return "确认解封选中的"
            case .delete: return "删除后不可恢复，确认删除选中的"
            }
        }

        var actionTitle: String {
            switch self {
            case .unfreeze: return "解冻"
            case .unban: return "解封"
            case .delete: return "删除"
            }
        }
    }

    var body: some View {
        Group {
            if isRegular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .task {
            await store.loadIfNeeded()
        }
        .sensoryFeedback(.selection, trigger: selectTick)
        .overlay(alignment: .top) {
            ToastBanner(message: $store.toast, isError: false)
        }
        .sheet(item: $statusAction) { target in
            ReasonSheet(
                title: target.title,
                count: store.selection.count,
                onConfirm: { reason in
                    Task {
                        await store.applyStatus(target.status, reason: reason)
                        statusAction = nil
                    }
                },
                onCancel: { statusAction = nil }
            )
            .presentationDetents([.height(320)])
        }
        .confirmationDialog(
            confirmTitle,
            isPresented: Binding(
                get: { confirmAction != nil },
                set: { if !$0 { confirmAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = confirmAction {
                Button(action.actionTitle, role: .destructive) {
                    confirmAction = nil
                    Task {
                        switch action {
                        case .unfreeze: await store.unfreeze()
                        case .unban: await store.unban()
                        case .delete: await store.deleteSelected()
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {
                confirmAction = nil
            }
        } message: {
            if confirmAction == .unban {
                Text("解封后回到「已发放」。")
            }
        }
    }

    /// 确认框标题 —— 与网页版文案一致。
    private var confirmTitle: String {
        guard let action = confirmAction else { return "" }
        return "\(action.message) \(store.selection.count) 张卡？"
    }

    // MARK: iPad 分栏

    private var regularLayout: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                filterBar
                selectionBar
                listContent
            }
            .frame(minWidth: 340, idealWidth: 420, maxWidth: 520)

            Divider()

            CardDetailView(card: selectedCard)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(.systemGroupedBackground))
        }
        .navigationTitle("卡密列表")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button("完成") { exitSelection() }
                        .fontWeight(.medium)
                } else {
                    layoutToggle
                    addButton
                }
            }
        }
    }

    // MARK: iPhone 单列

    private var compactLayout: some View {
        VStack(spacing: 0) {
            filterBar
            selectionBar
            listContent
        }
        .navigationTitle("卡密列表")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if isSelecting {
                    Button("完成") { exitSelection() }
                        .fontWeight(.medium)
                } else {
                    addButton
                }
            }
        }
    }

    // MARK: 工具栏

    private var layoutToggle: some View {
        Button {
            isGridMode.toggle()
        } label: {
            Image(systemName: isGridMode ? "list.bullet" : "square.grid.2x2")
        }
        .accessibilityLabel(isGridMode ? "切换为列表" : "切换为网格")
    }

    @ViewBuilder
    private var addButton: some View {
        if session.can(Permission.cardGenerate) {
            NavigationLink {
                CardGenerateView(store: store)
            } label: {
                Image(systemName: "plus")
            }
            .accessibilityLabel("生成卡密")
        }
    }

    // MARK: 筛选栏（网页版：卡密/批次 + 状态下拉）

    private var filterBar: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("输入编号或批次", text: $store.query.keyword)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit { Task { await store.reload() } }
                    if !store.query.keyword.isEmpty {
                        Button {
                            store.query.keyword = ""
                            Task { await store.reload() }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityLabel("卡密/批次")

                Menu {
                    Button {
                        store.query.status = nil
                        Task { await store.reload() }
                    } label: {
                        Label("全部", systemImage: store.query.status == nil ? "checkmark" : "")
                    }
                    Divider()
                    ForEach(CardStatus.allCases) { status in
                        Button {
                            store.query.status = status
                            Task { await store.reload() }
                        } label: {
                            Label(status.displayName, systemImage: store.query.status == status ? "checkmark" : "")
                        }
                    }
                } label: {
                    Image(systemName: store.query.status == nil
                          ? "line.3.horizontal.decrease.circle"
                          : "line.3.horizontal.decrease.circle.fill")
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("状态筛选")

                if isGridMode {
                    layoutToggle
                }
            }

            if let status = store.query.status {
                HStack(spacing: 6) {
                    Text("筛选：")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StatusBadge(title: status.displayName, color: status.color)
                    Button {
                        store.resetFilters()
                        Task { await store.reload() }
                    } label: {
                        Text("清除")
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    // MARK: 批量操作栏（网页版：选中后出现的操作按钮）

    @ViewBuilder
    private var selectionBar: some View {
        if !store.selection.isEmpty {
            HStack(spacing: 12) {
                Text("已选 \(store.selection.count) 张")
                    .font(.footnote.weight(.medium))

                Spacer()

                if session.can(Permission.cardStatus) {
                    Menu {
                        Button {
                            statusAction = StatusActionTarget(status: .frozen, title: "冻结")
                        } label: {
                            Label("冻结", systemImage: "snowflake")
                        }
                        Button {
                            statusAction = StatusActionTarget(status: .voided, title: "封禁")
                        } label: {
                            Label("封禁", systemImage: "nosign")
                        }
                    } label: {
                        Label("状态", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                    }

                    // 一个按钮顶原来两个：自动看选中项是冻结还是封禁，
                    // 冻结的送去解冻、封禁的送去解封，混选也能一次处理完。
                    Button {
                        Task { await store.restoreSelected() }
                    } label: {
                        Label("恢复", systemImage: "arrow.uturn.backward.circle")
                            .font(.footnote)
                    }
                    .disabled(!canRestoreSelected)
                }

                if session.can(Permission.cardRemove) {
                    Button(role: .destructive) {
                        confirmAction = .delete
                    } label: {
                        Label("删除", systemImage: "trash")
                            .font(.footnote)
                    }
                }

                Button {
                    store.selection.removeAll()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("取消选择")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.thinMaterial)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    // MARK: 列表内容

    @ViewBuilder
    private var listContent: some View {
        if store.state.isInitialLoad && store.items.isEmpty {
            StateView.loading("正在加载卡密…")
        } else if case .failed(let error) = store.state, store.items.isEmpty {
            StateView.failure(error) {
                Task { await store.reload() }
            }
        } else if store.items.isEmpty {
            StateView.empty(store.query.keyword.isEmpty ? "没有卡密" : "没有匹配的卡密")
        } else if isRegular && isGridMode {
            gridContent
        } else if isRegular {
            tableContent
        } else {
            listRows
        }
    }

    // MARK: iPad 表格（复刻网页版表格列）

    private var tableContent: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                tableHeader
                ForEach(store.items) { card in
                    tableRow(card)
                    Divider()
                }
                if store.isLoadingMore {
                    ProgressView().padding()
                }
            }
        }
        .refreshable {
            await store.reload()
        }
    }

    /// 表格头 —— 列顺序与网页版一致。
    private var tableHeader: some View {
        HStack(spacing: 0) {
            Text("卡密编号").frame(width: 150, alignment: .leading)
            Text("商品").frame(width: 90, alignment: .leading)
            Text("状态").frame(width: 76, alignment: .leading)
            Text("渠道").frame(width: 80, alignment: .leading)
            Text("到期").frame(width: 100, alignment: .leading)
            Text("订单号").frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func tableRow(_ card: CardKey) -> some View {
        HStack(spacing: 0) {
            Text(card.cardNo)
                .font(.caption.monospaced())
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)

            Text(card.productCode ?? "—")
                .font(.caption)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            StatusBadge(
                title: card.statusTitle,
                color: card.cardStatus?.color ?? .secondary
            )
            .frame(width: 76, alignment: .leading)

            Text(card.channelCode ?? "—")
                .font(.caption.monospaced())
                .frame(width: 80, alignment: .leading)
                .lineLimit(1)

            Text(expiryText(card))
                .font(.caption2)
                .foregroundStyle(expiryColor(card))
                .frame(width: 100, alignment: .leading)
                .lineLimit(1)

            Text(card.orderNo ?? "—")
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .background(isSelected(card) ? Color.accentColor.opacity(0.12) : Color.clear)
        .onTapGesture {
            if isSelecting {
                toggleSelection(card)
            } else {
                selectedCard = card
            }
        }
        // 长按进入多选 —— 这是「选中多张」最自然的入口。
        // 不能同时保留 .contextMenu：它也吃长按，两个手势会同时响应
        // （菜单弹出来的同时进了多选）。原来的右键菜单里的操作（冻结/封禁/删除）
        // 在选择栏里都有一份，所以去掉不影响能力。
        .onLongPressGesture(minimumDuration: 0.35) {
            enterSelection(card)
        }
    }

    private func isSelected(_ card: CardKey) -> Bool {
        store.selection.contains(card.id)
    }

    // MARK: 多选

    /// 选中项里有没有可以「恢复」的（冻结或封禁）。
    private var canRestoreSelected: Bool {
        store.items.contains { item in
            store.selection.contains(item.id)
                && (item.status == .frozen || item.status == .voided)
        }
    }

    /// 长按进入多选，并把当前这张带上。
    private func enterSelection(_ card: CardKey) {
        if !isSelecting {
            isSelecting = true
            selectTick += 1
        }
        if !store.selection.contains(card.id) {
            store.selection.insert(card.id)
        }
        selectedCard = card
    }

    /// 退出多选。
    private func exitSelection() {
        isSelecting = false
        store.selection.removeAll()
        selectTick += 1
    }

    /// 多选模式下点一张：切换它的选中态。
    private func toggleSelection(_ card: CardKey) {
        if store.selection.contains(card.id) {
            store.selection.remove(card.id)
            // 全取消就自动退出多选，省掉一次「完成」
            if store.selection.isEmpty {
                isSelecting = false
            }
        } else {
            store.selection.insert(card.id)
        }
        selectedCard = card
    }

    /// 到期文案 —— 网页版 `G()` 函数：空值显示「永久」，否则显示日期。
    private func expiryText(_ card: CardKey) -> String {
        if card.isPermanent { return "永久" }
        guard let date = card.expireDate else { return "—" }
        return CardDetailView.formatShortDate(date)
    }

    private func expiryColor(_ card: CardKey) -> Color {
        if card.isPermanent { return .secondary }
        if let days = card.remainingDays, days < 0 { return .red }
        if let days = card.remainingDays, days <= 7 { return .orange }
        return .secondary
    }

    // MARK: iPhone 列表

    private var listRows: some View {
        List {
            Section {
                ForEach(store.items) { card in
                    if isSelecting {
                        // 多选模式：点一下切换选中，不再进详情
                        cardRow(card)
                            .contentShape(Rectangle())
                            .onTapGesture { toggleSelection(card) }
                            .listRowBackground(
                                isSelected(card)
                                ? Color.accentColor.opacity(0.12)
                                : Color.clear
                            )
                    } else {
                        NavigationLink {
                            CardDetailView(card: card)
                        } label: {
                            cardRow(card)
                        }
                        // 用 simultaneousGesture 而不是 onLongPressGesture：
                        // NavigationLink 自己吞手势，普通长按收不到事件。
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35).onEnded { _ in
                                enterSelection(card)
                            }
                        )
                    }
                }
            } header: {
                Text("共 \(store.total) 张")
                    .font(.caption)
            } footer: {
                if store.isLoadingMore {
                    HStack {
                        Spacer()
                        ProgressView().controlSize(.small)
                        Spacer()
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await store.reload()
        }
    }

    private func cardRow(_ card: CardKey) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(card.cardNo)
                    .font(.body.monospaced().weight(.medium))
                Spacer()
                StatusBadge(
                    title: card.statusTitle,
                    color: card.cardStatus?.color ?? .secondary
                )
            }

            HStack(spacing: 12) {
                Label(card.deviceDisplay, systemImage: "iphone")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(expiryText(card))
                    .font(.caption)
                    .foregroundStyle(expiryColor(card))
            }

            HStack(spacing: 12) {
                if let product = card.productCode, !product.isEmpty {
                    Label(product, systemImage: "shippingbox")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let channel = card.channelCode, !channel.isEmpty {
                    Label(channel, systemImage: "arrow.triangle.branch")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: 网格

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 220, maximum: 340), spacing: 12)],
                spacing: 12
            ) {
                ForEach(store.items) { card in
                    CardGridCell(card: card, isSelected: store.selection.contains(card.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if isSelecting {
                                toggleSelection(card)
                            } else {
                                selectedCard = card
                            }
                        }
                        .onLongPressGesture(minimumDuration: 0.35) {
                            enterSelection(card)
                        }
                }
            }
            .padding(12)

            if store.isLoadingMore {
                ProgressView().padding()
            }
        }
        .refreshable {
            await store.reload()
        }
    }
}

// MARK: - 网格单元格

/// iPad 网格模式下的卡密单元格。
struct CardGridCell: View {
    let card: CardKey
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(card.cardNo)
                    .font(.subheadline.monospaced().weight(.semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            StatusBadge(
                title: card.statusTitle,
                color: card.cardStatus?.color ?? .secondary
            )

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                infoLine("shippingbox", card.productCode ?? "—")
                infoLine("arrow.triangle.branch", card.channelCode ?? "—")
                infoLine("iphone", card.deviceDisplay)
                if let days = card.remainingDays, !card.isPermanent {
                    infoLine("clock", "剩余 \(days) 天")
                } else if card.isPermanent {
                    infoLine("infinity", "永久")
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(isSelected ? Color.accentColor : .clear, lineWidth: 2)
        )
    }

    private func infoLine(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

// MARK: - 原因输入弹窗

/// 冻结 / 封禁时填写原因。
///
/// 对应接口字段 `reason`（前端用 `reason || "后台操作"` 兜底）。
/// 弹窗标题对齐网页版：「把选中的 N 张卡冻结，请填原因」。
struct ReasonSheet: View {
    let title: String
    let count: Int
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var reason: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("原因（可留空）", text: $reason, axis: .vertical)
                        .lineLimit(2...4)
                        .focused($focused)
                } header: {
                    Text("把选中的 \(count) 张卡\(title)，请填原因")
                } footer: {
                    Text("原因会记录到操作日志，便于日后追溯。留空则记为「后台操作」。")
                }
            }
            .navigationTitle("\(title)卡密")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认\(title)") {
                        onConfirm(reason.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear { focused = true }
    }
}
