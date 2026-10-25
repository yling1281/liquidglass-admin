import Foundation
import SwiftUI

// MARK: - 卡密列表 Store

/// 卡密列表的加载 / 筛选 / 缓存 / 刷新。
///
/// 设计要点：
/// - **缓存**：列表数据常驻内存，切走再回来不必重新拉；下拉刷新才强制重取。
/// - **分页**：上拉加载更多（`pageNum` 递增，追加到 `items`）。
/// - **刷新**：`.refreshable` 保留旧列表并显示顶部进度，失败时**不清空**已有数据，
///   而是弹一个可重试的提示条 —— 这样网络抖动不会让用户看到空列表。
@MainActor
final class CardListStore: ObservableObject {

    @Published private(set) var items: [CardKey] = []
    @Published private(set) var total: Int = 0
    @Published private(set) var state: LoadState<[CardKey]> = .idle
    @Published private(set) var isLoadingMore: Bool = false
    @Published private(set) var hasMore: Bool = true

    /// 批量选择（iPad 表格多选 / iPhone 编辑模式共用）。
    @Published var selection: Set<Int> = []

    /// 顶部的瞬时提示（如「已冻结 3 张」）。
    @Published var toast: String?

    @Published var query: CardQuery = CardQuery() {
        didSet {
            guard query != oldValue else { return }
            // 搜索关键词变化 → 重置到第一页
            if query.pageNum == 1, query.keyword != oldValue.keyword || query.status != oldValue.status {
                Task { await reload() }
            }
        }
    }

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 首次加载（无缓存时）。
    func loadIfNeeded() async {
        guard items.isEmpty else { return }
        await reload()
    }

    /// 强制重载第一页。
    func reload() async {
        query.pageNum = 1
        state = .loading
        selection.removeAll()

        do {
            let response = try await fetch(page: 1)
            items = response.rows
            total = response.total
            hasMore = response.rows.count >= query.pageSize
            state = .loaded(response.rows)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    /// 加载下一页。
    func loadMore() async {
        guard !isLoadingMore, hasMore, !state.isInitialLoad else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        let nextPage = query.pageNum + 1
        let savedPage = query.pageNum
        query.pageNum = nextPage

        do {
            let response = try await fetch(page: nextPage)
            // 去重（后端翻页边界可能重复同一条）
            let existing = Set(items.map(\.id))
            items.append(contentsOf: response.rows.filter { !existing.contains($0.id) })
            total = response.total
            hasMore = response.rows.count >= query.pageSize
        } catch {
            // 加载更多失败：回滚页码，保留已有数据
            query.pageNum = savedPage
            toast = error.localizedDescription
        }
    }

    /// 清空筛选。
    func resetFilters() {
        query.keyword = ""
        query.status = nil
        query.pageNum = 1
    }

    // MARK: 批量操作

    /// 对选中的卡执行状态变更。
    func applyStatus(_ status: CardStatus, reason: String) async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }

        do {
            let result = try await client.send(
                APIRequest(
                    endpoint: APIEndpoint.cardStatus,
                    body: CardStatusRequest(ids: ids, status: status, reason: reason).body
                ),
                as: BatchOperationResult.self
            )
            let success = result.success ?? 0
            let skipped = result.skipped ?? []
            if skipped.isEmpty {
                toast = "成功 \(success) 张"
            } else {
                toast = "成功 \(success) 张，跳过 \(skipped.count) 张（\(result.skippedDescription)）"
            }
            selection.removeAll()
            await reload()
        } catch let error as APIError {
            toast = error.localizedDescription
        } catch {
            toast = error.localizedDescription
        }
    }

    /// 解冻。
    func unfreeze() async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        await runSimpleOperation(endpoint: APIEndpoint.cardUnfreeze, ids: ids, label: "解冻")
    }

    /// 解封。
    func unban() async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        await runSimpleOperation(endpoint: APIEndpoint.cardUnban, ids: ids, label: "解封")
    }

    /// 按选中项的**实际状态**自动恢复：冻结的送去解冻，封禁的送去解封。
    ///
    /// 为什么要有这个：选中的一批卡往往混着冻结和封禁两种状态，
    /// 用户不可能先逐条看清再分别点两个按钮。这里按状态拆成两批，
    /// 各走各的接口，最后把结果合并成一句提示。
    func restoreSelected() async {
        guard !selection.isEmpty else { return }

        let chosen = items.filter { selection.contains($0.id) }
        let frozen = chosen.filter { $0.status == .frozen }.map(\.id)
        let banned = chosen.filter { $0.status == .voided }.map(\.id)

        if frozen.isEmpty && banned.isEmpty {
            toast = "选中的卡里没有冻结或封禁状态的"
            return
        }

        var parts: [String] = []
        if !frozen.isEmpty {
            let count = await simpleRestore(endpoint: APIEndpoint.cardUnfreeze, ids: frozen)
            parts.append(count >= 0 ? "解冻 \(count) 张" : "解冻失败")
        }
        if !banned.isEmpty {
            let count = await simpleRestore(endpoint: APIEndpoint.cardUnban, ids: banned)
            parts.append(count >= 0 ? "解封 \(count) 张" : "解封失败")
        }

        selection.removeAll()
        toast = parts.joined(separator: "，")
        await reload()
    }

    /// 恢复类操作：返回成功条数，失败返回 `-1`。
    private func simpleRestore(endpoint: Endpoint, ids: [Int]) async -> Int {
        do {
            let result = try await client.send(
                APIRequest(endpoint: endpoint, body: ["ids": ids]),
                as: BatchOperationResult.self
            )
            return result.success ?? 0
        } catch {
            return -1
        }
    }

    /// 删除。
    func deleteSelected() async {
        let ids = Array(selection)
        guard !ids.isEmpty else { return }
        await runSimpleOperation(
            endpoint: APIEndpoint.cardDelete(ids: ids),
            ids: ids,
            label: "删除",
            body: nil
        )
    }

    private func runSimpleOperation(
        endpoint: Endpoint,
        ids: [Int],
        label: String,
        body: [String: Any]? = nil
    ) async {
        do {
            let result = try await client.send(
                APIRequest(endpoint: endpoint, body: body ?? ["ids": ids]),
                as: BatchOperationResult.self
            )
            toast = "已\(label) \(result.success ?? 0) 张"
            selection.removeAll()
            await reload()
        } catch let error as APIError {
            toast = error.localizedDescription
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: 私有

    private func fetch(page: Int) async throws -> PagedResponse<CardKey> {
        let data = try await client.sendRaw(APIRequest(
            endpoint: APIEndpoint.cardList,
            query: query.queryItems()
        ))
        return try JSONDecoder().decode(PagedResponse<CardKey>.self, from: data)
    }
}

// MARK: - 统计 Store

/// 统计面板的数据源。
///
/// ⚠️ 服务端**没有**统计接口，数字是按前端首页同样的方式算出来的：
/// 用多次 `list` 的 `total` 求和。各状态通过带 `status` 参数的列表查询拿到总数。
///
/// 「在线设备」「今日激活」「到期预警」需要按 `expireAt` / `createTime` 逐条判断，
/// 服务端没有对应聚合接口，所以这里**拉取全量卡密后在本地算**。
/// 数据量小时准确；卡密上千后这次拉取会变慢 —— 故限制最多取 1000 条，
/// 超出时在界面上标注「基于最近 1000 条估算」。
@MainActor
final class CardStatisticsStore: ObservableObject {

    @Published private(set) var statistics = CardStatistics()
    @Published private(set) var state: LoadState<CardStatistics> = .idle
    /// 统计口径说明（数据量大时会显示「估算」）。
    @Published private(set) var isApproximate: Bool = false

    private let client: APIClient
    private let maxScan = 1000

    init(client: APIClient = .shared) {
        self.client = client
    }

    func load() async {
        state = .loading
        do {
            var stats = CardStatistics()

            // 各状态总数（服务端 status 筛选直接支持）。
            async let totalCount = fetchTotal(status: nil)
            async let unissued = fetchTotal(status: .unissued)
            async let issued = fetchTotal(status: .issued)
            async let used = fetchTotal(status: .used)
            async let frozen = fetchTotal(status: .frozen)
            async let voided = fetchTotal(status: .voided)
            async let expired = fetchTotal(status: .expired)

            stats.total = try await totalCount
            stats.unissued = try await unissued
            stats.issued = try await issued
            stats.used = try await used
            stats.frozen = try await frozen
            stats.voided = try await voided
            stats.expired = try await expired

            // 需要逐条判断的三项：拉全量（上限 maxScan）本地算。
            let all = try await fetchAll()
            isApproximate = all.count < stats.total

            let now = Date()
            let calendar = Calendar.current
            let startOfToday = calendar.startOfDay(for: now)
            let sevenDaysLater = now.addingTimeInterval(7 * 86400)

            var online = 0
            var todayActivated = 0
            var expiringSoon = 0

            for card in all {
                // 在线设备：绑定了设备且未过期
                if card.bindDevice?.isEmpty == false,
                   card.cardStatus != .expired,
                   card.cardStatus != .voided {
                    online += 1
                }
                // 今日激活：今日创建且状态不是未发放
                if let created = card.createDate,
                   created >= startOfToday,
                   card.status != CardStatus.unissued.rawValue {
                    todayActivated += 1
                }
                // 7 天内到期
                if let expire = card.expireDate,
                   expire > now,
                   expire <= sevenDaysLater {
                    expiringSoon += 1
                }
            }

            stats.onlineDevices = online
            stats.todayActivated = todayActivated
            stats.expiringSoon = expiringSoon

            statistics = stats
            state = .loaded(stats)
        } catch let error as APIError {
            state = .failed(error)
        } catch {
            state = .failed(.transport(error.localizedDescription))
        }
    }

    private func fetchTotal(status: CardStatus?) async throws -> Int {
        var items: [String: String?] = [
            "pageNum": "1",
            "pageSize": "1",
        ]
        if let status {
            items["status"] = status.apiValue
        }
        let data = try await client.sendRaw(APIRequest(
            endpoint: APIEndpoint.cardList,
            query: items
        ))
        let response = try JSONDecoder().decode(PagedResponse<CardKey>.self, from: data)
        return response.total
    }

    private func fetchAll() async throws -> [CardKey] {
        let data = try await client.sendRaw(APIRequest(
            endpoint: APIEndpoint.cardList,
            query: ["pageNum": "1", "pageSize": String(maxScan)]
        ))
        let response = try JSONDecoder().decode(PagedResponse<CardKey>.self, from: data)
        return response.rows
    }
}
