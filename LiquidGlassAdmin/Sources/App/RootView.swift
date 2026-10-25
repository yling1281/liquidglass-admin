import SwiftUI

// MARK: - 主框架（底部标签栏）

/// 主框架。
///
/// **改成底部标签栏**（原来 iPhone 是顶部菜单、iPad 是侧边栏）：
/// 顶部菜单要展开才知道有什么，底部栏一眼能看到全部入口，少一次点击。
///
/// 四个 Tab：
/// - **总览**：卡密统计（原来的统计首页）
/// - **店铺**：店铺后台（acg-faka）的 23 个模块
/// - **卡密**：卡密列表与批量操作
/// - **我的**：账号、QQ 绑定、服务器、其余功能入口
struct RootView: View {

    @EnvironmentObject private var session: SessionStore

    @StateObject private var shopAdmin = ShopAdminSession()
    @State private var tab: Tab = .overview

    @State private var cardStore = CardListStore()
    @State private var statisticsStore = CardStatisticsStore()
    @State private var recordStore = RecordListStore()
    @State private var channelStore = ChannelListStore()
    @State private var shopStore = ShopStore()
    @State private var integrationStore = IntegrationStore()

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    /// 底部标签。
    enum Tab: String, Hashable, CaseIterable {
        case overview
        case shop
        case cards
        case me

        var title: String {
            switch self {
            case .overview: return "总览"
            case .shop: return "店铺"
            case .cards: return "卡密"
            case .me: return "我的"
            }
        }

        var icon: String {
            switch self {
            case .overview: return "chart.bar.xaxis"
            case .shop: return "storefront.fill"
            case .cards: return "key.fill"
            case .me: return "person.crop.circle"
            }
        }
    }

    var body: some View {
        TabView(selection: $tab) {
            overviewTab
                .tabItem { Label(Tab.overview.title, systemImage: Tab.overview.icon) }
                .tag(Tab.overview)

            shopTab
                .tabItem { Label(Tab.shop.title, systemImage: Tab.shop.icon) }
                .tag(Tab.shop)
                .badge(shopAdmin.isLoggedIn ? 0 : nil)

            cardsTab
                .tabItem { Label(Tab.cards.title, systemImage: Tab.cards.icon) }
                .tag(Tab.cards)

            meTab
                .tabItem { Label(Tab.me.title, systemImage: Tab.me.icon) }
                .tag(Tab.me)
        }
        .task {
            await statisticsStore.load()
            await shopAdmin.refresh()
        }
    }

    // MARK: 总览

    private var overviewTab: some View {
        NavigationStack {
            DashboardView(store: statisticsStore)
        }
    }

    // MARK: 店铺

    private var shopTab: some View {
        NavigationStack {
            Group {
                if shopAdmin.isLoggedIn {
                    ShopAdminHomeView(client: shopAdmin)
                } else {
                    ShopAdminLoginView(shopAdmin: shopAdmin, session: session)
                }
            }
        }
    }

    // MARK: 卡密

    private var cardsTab: some View {
        NavigationStack {
            CardListView(
                store: cardStore,
                session: session,
                isRegular: isRegular
            )
        }
    }

    // MARK: 我的

    private var meTab: some View {
        NavigationStack {
            SettingsView(
                session: session,
                shopStore: shopStore,
                shopAdmin: shopAdmin,
                recordStore: recordStore,
                channelStore: channelStore,
                integrationStore: integrationStore
            )
        }
    }
}
