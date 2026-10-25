import SwiftUI

// MARK: - 导航分区

/// 侧边栏的分区。
enum SidebarSection: String, CaseIterable, Identifiable, Hashable {
    case dashboard
    case cards
    case records
    case channels
    case shop
    case integration
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "统计"
        case .cards: return "卡密管理"
        case .records: return "操作记录"
        case .channels: return "发卡渠道"
        case .shop: return "店铺管理"
        case .integration: return "对接情况"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .dashboard: return "chart.bar.xaxis"
        case .cards: return "key.fill"
        case .records: return "clock.arrow.circlepath"
        case .channels: return "arrow.triangle.branch"
        case .shop: return "storefront.fill"
        case .integration: return "point.3.connected.trianglepath.dotted"
        case .settings: return "gearshape.fill"
        }
    }

    /// 需要的权限点（没有权限的分区在侧边栏里禁用）。
    var requiredPermission: String? {
        switch self {
        case .cards: return Permission.cardList
        case .records: return Permission.recordList
        case .channels: return Permission.channelList
        case .dashboard, .shop, .integration, .settings: return nil
        }
    }
}

// MARK: - 主框架

/// 主框架视图。
///
/// **响应式策略**：
/// - **iPhone（compact）**：单列。`NavigationStack` 推栈，统计页是列表，卡密页是列表+详情推栈。
/// - **iPad（regular）**：`NavigationSplitView` 三栏（侧边栏 / 内容 / 详情），
///   侧边栏常驻，内容区与详情区并列；卡密列表在宽空间下变成**多列网格**。
/// - **横竖屏切换**：用 `horizontalSizeClass` 判定，而不是硬编码设备类型 ——
///   iPad 分屏成窄条时会退回单列，横过来又变回分栏，布局随之重建。
struct RootView: View {

    @EnvironmentObject private var session: SessionStore
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var selection: SidebarSection? = .dashboard
    @State private var cardStore = CardListStore()
    @State private var statisticsStore = CardStatisticsStore()
    @State private var recordStore = RecordListStore()
    @State private var channelStore = ChannelListStore()
    @State private var shopStore = ShopStore()
    @State private var integrationStore = IntegrationStore()

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if isRegular {
                regularLayout
            } else {
                compactLayout
            }
        }
        .task {
            // 登录后自动拉一次统计，其他页面进入时再拉。
            await statisticsStore.load()
        }
    }

    // MARK: iPad 分栏

    private var regularLayout: some View {
        NavigationSplitView {
            // SidebarView 内部用 @EnvironmentObject 取 session，不需要显式传参。
            SidebarView(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 320)
        } detail: {
            NavigationStack {
                content(for: selection ?? .dashboard)
            }
        }
        .navigationSplitViewStyle(.balanced)
    }

    // MARK: iPhone 单列

    private var compactLayout: some View {
        NavigationStack {
            content(for: selection ?? .dashboard)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Menu {
                            ForEach(SidebarSection.allCases) { section in
                                Button {
                                    selection = section
                                } label: {
                                    Label(section.title, systemImage: section.systemImage)
                                }
                                .disabled(!isEnabled(section))
                            }
                        } label: {
                            Label(
                                (selection ?? .dashboard).title,
                                systemImage: (selection ?? .dashboard).systemImage
                            )
                        }
                    }
                }
        }
    }

    // MARK: 内容分发

    @ViewBuilder
    private func content(for section: SidebarSection) -> some View {
        switch section {
        case .dashboard:
            DashboardView(store: statisticsStore)
        case .cards:
            CardListView(
                store: cardStore,
                session: session,
                isRegular: isRegular
            )
        case .records:
            RecordListView(store: recordStore)
        case .channels:
            ChannelListView(store: channelStore)
        case .shop:
            ShopManagementView(store: shopStore)
        case .integration:
            IntegrationView(store: integrationStore, shopStore: shopStore)
        case .settings:
            SettingsView(session: session, shopStore: shopStore)
        }
    }

    private func isEnabled(_ section: SidebarSection) -> Bool {
        guard let permission = section.requiredPermission else { return true }
        return session.can(permission)
    }
}

// MARK: - 侧边栏

/// iPad 侧边栏。
struct SidebarView: View {

    @Binding var selection: SidebarSection?
    @EnvironmentObject private var session: SessionStore

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarSection.allCases) { section in
                    NavigationLink(value: section) {
                        Label(section.title, systemImage: section.systemImage)
                    }
                    .disabled(!isEnabled(section))
                }
            } header: {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill")
                        .foregroundStyle(.tint)
                    Text("零砚后台")
                        .font(.headline)
                }
                .padding(.bottom, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("卡密中心")
    }

    private func isEnabled(_ section: SidebarSection) -> Bool {
        guard let permission = section.requiredPermission else { return true }
        return session.can(permission)
    }
}
