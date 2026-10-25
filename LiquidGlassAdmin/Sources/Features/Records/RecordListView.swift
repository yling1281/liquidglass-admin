import Foundation
import SwiftUI

// MARK: - 操作记录 Store

/// 操作记录列表。
///
/// 对应接口：`GET /card/record/list?pageNum=&pageSize=`
/// 响应：顶层 `rows` / `total`。
@MainActor
final class RecordListStore: ObservableObject {

    @Published private(set) var items: [CardRecord] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var state: LoadState<[CardRecord]> = .idle
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = true
    @Published var toast: String?

    @Published var pageNum: Int = 1
    @Published var pageSize: Int = 30

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    func reload() async {
        pageNum = 1
        state = .loading
        do {
            let response = try await fetch(page: 1)
            items = response.rows
            total = response.total
            hasMore = response.rows.count >= pageSize
            state = .loaded(response.rows)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    func loadMore() async {
        guard !isLoadingMore, hasMore, !state.isInitialLoad else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let next = pageNum + 1
        pageNum = next
        do {
            let response = try await fetch(page: next)
            let existing = Set(items.map(\.id))
            items.append(contentsOf: response.rows.filter { !existing.contains($0.id) })
            total = response.total
            hasMore = response.rows.count >= pageSize
        } catch {
            pageNum = next - 1
            toast = error.localizedDescription
        }
    }

    private func fetch(page: Int) async throws -> PagedResponse<CardRecord> {
        let data = try await client.sendRaw(APIRequest(
            endpoint: APIEndpoint.recordList,
            query: ["pageNum": String(page), "pageSize": String(pageSize)]
        ))
        return try JSONDecoder().decode(PagedResponse<CardRecord>.self, from: data)
    }
}

// MARK: - 操作记录视图

/// 操作记录列表页。
struct RecordListView: View {

    @ObservedObject var store: RecordListStore

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Group {
            if store.state.isInitialLoad && store.items.isEmpty {
                StateView.loading("正在加载操作记录…")
            } else if case .failed(let error) = store.state, store.items.isEmpty {
                StateView.failure(error) {
                    Task { await store.reload() }
                }
            } else if store.items.isEmpty {
                StateView.empty("还没有操作记录")
            } else if isRegular {
                tableLayout
            } else {
                listLayout
            }
        }
        .navigationTitle("操作记录")
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
        .overlay(alignment: .top) {
            ToastBanner(message: $store.toast, isError: true)
        }
        .task {
            await store.loadIfNeeded()
        }
    }

    // MARK: iPad 表格

    private var tableLayout: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                headerRow
                ForEach(store.items) { record in
                    recordRow(record)
                    Divider()
                }
                if store.isLoadingMore {
                    ProgressView().padding()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("卡号").frame(width: 150, alignment: .leading)
            Text("动作").frame(width: 80, alignment: .leading)
            Text("状态变化").frame(width: 130, alignment: .leading)
            Text("来源").frame(width: 70, alignment: .leading)
            Text("操作者").frame(width: 90, alignment: .leading)
            Text("备注").frame(maxWidth: .infinity, alignment: .leading)
            Text("时间").frame(width: 150, alignment: .trailing)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func recordRow(_ record: CardRecord) -> some View {
        HStack(spacing: 12) {
            Text(record.cardNo ?? "—")
                .font(.caption.monospaced())
                .frame(width: 150, alignment: .leading)
                .lineLimit(1)

            Text(record.actionTitle)
                .font(.caption)
                .frame(width: 80, alignment: .leading)

            Text(record.statusTransition ?? "—")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .leading)
                .lineLimit(1)

            Text(record.sourceTitle)
                .font(.caption)
                .frame(width: 70, alignment: .leading)

            Text(record.operator ?? "—")
                .font(.caption)
                .frame(width: 90, alignment: .leading)
                .lineLimit(1)

            Text(record.remark ?? "—")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .lineLimit(1)

            Text(record.createDate.map(CardDetailView.format) ?? "—")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: iPhone 列表

    private var listLayout: some View {
        List {
            ForEach(store.items) { record in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(record.cardNo ?? "—")
                            .font(.subheadline.monospaced().weight(.medium))
                        Spacer()
                        Text(record.actionTitle)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }

                    if let transition = record.statusTransition {
                        HStack(spacing: 6) {
                            Text(transition)
                            Text("·")
                            Text(record.sourceTitle)
                            if let operatorName = record.operator, !operatorName.isEmpty {
                                Text("·")
                                Text(operatorName)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if let remark = record.remark, !remark.isEmpty {
                        Text(remark)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(2)
                    }

                    Text(record.createDate.map(CardDetailView.format) ?? "—")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }

            if store.isLoadingMore {
                HStack {
                    Spacer()
                    ProgressView().controlSize(.small)
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
    }
}
