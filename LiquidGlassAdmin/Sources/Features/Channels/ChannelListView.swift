import Foundation
import SwiftUI

// MARK: - 渠道 Store

/// 发卡渠道列表。
///
/// 对应接口：`GET /card/channel/list` → 顶层 `rows` / `total`。
@MainActor
final class ChannelListStore: ObservableObject {

    @Published private(set) var items: [CardChannel] = []
    @Published private(set) var state: LoadState<[CardChannel]> = .idle
    @Published var toast: String?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        state = .loading
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.channelList))
            let response = try JSONDecoder().decode(PagedResponse<CardChannel>.self, from: data)
            items = response.rows
            state = .loaded(response.rows)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }
}

// MARK: - 渠道视图

/// 发卡渠道页。
struct ChannelListView: View {

    @ObservedObject var store: ChannelListStore

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if store.state.isInitialLoad && store.items.isEmpty {
                StateView.loading("正在加载渠道…")
            } else if case .failed(let error) = store.state, store.items.isEmpty {
                StateView.failure(error) {
                    Task { await store.reload() }
                }
            } else if store.items.isEmpty {
                StateView.empty("没有配置任何发卡渠道")
            } else if isRegular {
                gridLayout
            } else {
                listLayout
            }
        }
        .navigationTitle("发卡渠道")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.reload() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
        .refreshable {
            await store.reload()
        }
        .task {
            await store.loadIfNeeded()
        }
    }

    private var gridLayout: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 260, maximum: 420), spacing: 12)],
                spacing: 12
            ) {
                ForEach(store.items) { channel in
                    channelCard(channel)
                }
            }
            .padding()
        }
    }

    private var listLayout: some View {
        List {
            ForEach(store.items) { channel in
                channelCard(channel)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }
        }
        .listStyle(.plain)
    }

    private func channelCard(_ channel: CardChannel) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(channel.channelName)
                        .font(.headline)
                    Text(channel.channelCode)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusBadge(
                    title: channel.enabled ? "已启用" : "未启用",
                    color: channel.enabled ? .green : .secondary
                )
            }

            if let remark = channel.remark, !remark.isEmpty {
                Text(remark)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }
}
