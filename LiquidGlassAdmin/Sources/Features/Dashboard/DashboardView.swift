import SwiftUI

// MARK: - 统计面板

/// 统计面板。
///
/// 布局：
/// - iPhone（compact）：单列，`LazyVGrid` 两列排布统计块。
/// - iPad（regular）：三列，统计块更宽，额外给出「到期预警」与「渠道概览」分区。
struct DashboardView: View {

    @ObservedObject var store: CardStatisticsStore

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isRegular {
                    summaryGrid
                    detailSection
                } else {
                    summaryGrid
                    detailSection
                }            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("统计")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.load() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(store.state.isLoading)
                .accessibilityLabel("刷新统计")
            }
        }
        .refreshable {
            await store.load()
        }
        .overlay {
            switch store.state {
            case .loading where store.statistics.total == 0:
                StateView.loading("正在统计…")
            case .failed(let error) where store.statistics.total == 0:
                StateView.failure(error) {
                    Task { await store.load() }
                }
            default:
                EmptyView()
            }
        }
    }

    // MARK: 概览

    private var summaryGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("卡密总览")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12)],
                spacing: 12
            ) {
                StatTile(
                    title: "总数",
                    value: "\(store.statistics.total)",
                    systemImage: "key.fill"
                )
                StatTile(
                    title: "已激活",
                    value: "\(store.statistics.activated)",
                    systemImage: "checkmark.seal.fill",
                    tint: .green,
                    caption: "已发放 + 已使用"
                )
                StatTile(
                    title: "未激活",
                    value: "\(store.statistics.notActivated)",
                    systemImage: "tray",
                    tint: .secondary
                )
                StatTile(
                    title: "在线设备",
                    value: "\(store.statistics.onlineDevices)",
                    systemImage: "antenna.radiowaves.left.and.right",
                    tint: .blue,
                    caption: store.isApproximate ? "基于最近 1000 条估算" : "已绑定设备且未失效"
                )
                StatTile(
                    title: "今日激活",
                    value: "\(store.statistics.todayActivated)",
                    systemImage: "sparkles",
                    tint: .orange,
                    caption: store.isApproximate ? "基于最近 1000 条估算" : "今日创建且已发放"
                )
                StatTile(
                    title: "7 天内到期",
                    value: "\(store.statistics.expiringSoon)",
                    systemImage: "clock.badge.exclamationmark",
                    tint: .red,
                    caption: store.isApproximate ? "基于最近 1000 条估算" : "需提醒续期"
                )
            }
        }
    }

    // MARK: 状态分布

    private var detailSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("状态分布")
                .font(.headline)

            VStack(spacing: 0) {
                statusRow(.unissued, count: store.statistics.unissued)
                Divider()
                statusRow(.issued, count: store.statistics.issued)
                Divider()
                statusRow(.used, count: store.statistics.used)
                Divider()
                statusRow(.frozen, count: store.statistics.frozen)
                Divider()
                statusRow(.voided, count: store.statistics.voided)
                Divider()
                statusRow(.expired, count: store.statistics.expired)
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("口径说明：服务端没有统计接口，数字与网页版后台首页一致 —— 由各状态的列表总数汇总得出。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 4)
        }
    }

    private func statusRow(_ status: CardStatus, count: Int) -> some View {
        HStack {
            StatusBadge(title: status.displayName, color: status.color)
            Spacer()
            Text("\(count)")
                .font(.body.weight(.semibold))
                .monospacedDigit()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
