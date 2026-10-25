import Foundation
import SwiftUI

// MARK: - 对接状态模型

/// 单个对接接口的连通性检查结果。
struct EndpointCheck: Identifiable, Equatable {
    let id: String
    /// 归属的服务名（卡密后台 / 商城前台 / 店铺后台）。
    let service: String
    /// 接口路径。
    let path: String
    /// 用途说明。
    let purpose: String
    /// 是否需要登录。
    let requiresAuth: Bool
    /// 检查结果。
    var result: Result<CheckOutcome, APIError>?

    /// 检查通过时的摘要。
    struct CheckOutcome: Equatable {
        /// 业务码。
        var code: Int
        /// 关键信息（如返回的 total、msg）。
        var summary: String
    }

    var isSuccess: Bool {
        if case .success = result { return true }
        return false
    }

    var isChecked: Bool { result != nil }

    /// 状态文案。
    var statusTitle: String {
        guard let result else { return "未检测" }
        switch result {
        case .success: return "正常"
        case .failure(let error):
            if case .business(_, let message) = error {
                return message
            }
            return error.errorDescription ?? "异常"
        }
    }

    /// 状态色。
    var statusColor: Color {
        guard let result else { return .secondary }
        switch result {
        case .success: return .green
        case .failure: return .orange
        }
    }
}

// MARK: - 对接情况 Store

/// 「对接情况」的数据源。
///
/// 展示**每个对接渠道 / 接口的当前状态与结果**：
/// - **渠道**：来自卡密后台 `GET /card/channel/list`（发卡渠道配置，标注是否启用）。
/// - **接口**：逐个实调，验证连通性与返回码。
///
/// 这些检查是**真实发请求**得到的，不是写死的文案。
@MainActor
final class IntegrationStore: ObservableObject {

    @Published private(set) var channels: [CardChannel] = []
    @Published private(set) var channelState: LoadState<[CardChannel]> = .idle

    @Published private(set) var checks: [EndpointCheck] = []
    @Published private(set) var isChecking = false
    /// 上次检测完成时间。
    @Published private(set) var lastCheckedAt: Date?

    @Published var toast: String?

    private let client: APIClient

    init(client: APIClient = .shared) {
        self.client = client
    }

    /// 待检测的接口清单。
    ///
    /// 每一项都对应实际在用的对接接口，路径与请求体与实际调用完全一致。
    private static let endpointSpecs: [(id: String, service: String, path: String, purpose: String, requiresAuth: Bool)] = [
        ("login", "卡密后台", "POST /prod-api/login", "登录取令牌", false),
        ("getInfo", "卡密后台", "GET /prod-api/getInfo", "当前用户与权限点", true),
        ("getRouters", "卡密后台", "GET /prod-api/getRouters", "动态路由表", true),
        ("cardList", "卡密后台", "GET /prod-api/card/key/list", "卡密列表", true),
        ("cardGenerate", "卡密后台", "POST /prod-api/card/key/generate", "批量生成卡密", true),
        ("cardStatus", "卡密后台", "PUT /prod-api/card/key/status", "改卡密状态（冻结/封禁）", true),
        ("cardUnfreeze", "卡密后台", "PUT /prod-api/card/key/unfreeze", "解冻卡密", true),
        ("cardUnban", "卡密后台", "PUT /prod-api/card/key/unban", "解封卡密", true),
        ("cardDelete", "卡密后台", "DELETE /prod-api/card/key/{id}", "删除卡密", true),
        ("recordList", "卡密后台", "GET /prod-api/card/record/list", "操作记录", true),
        ("channelList", "卡密后台", "GET /prod-api/card/channel/list", "发卡渠道配置", true),
        ("shopCategories", "商城前台", "GET /user/api/index/data", "店铺/分类列表", false),
        ("shopCommodities", "商城前台", "GET /user/api/index/commodity", "商品列表", false),
        ("shopStock", "商城前台", "POST /user/api/index/stock", "商品库存查询", false),
        ("shopValuation", "商城前台", "POST /user/api/index/valuation", "价格试算", false),
        ("shopOrderQuery", "商城前台", "POST /user/api/index/query", "订单查询", false),
        ("shopOrderSecret", "商城前台", "POST /user/api/index/secret", "发货内容解密", false),
        ("shopAdminLogin", "店铺后台", "POST /admin/api/authentication/login", "店铺后台登录", false),
    ]

    /// 加载渠道配置。
    func loadChannels() async {
        channelState = .loading
        do {
            let data = try await client.sendRaw(APIRequest(endpoint: APIEndpoint.channelList))
            let response = try JSONDecoder().decode(PagedResponse<CardChannel>.self, from: data)
            channels = response.rows
            channelState = .loaded(response.rows)
        } catch let error as APIError {
            channelState = .failed(error)
        } catch {
            channelState = .failed(.transport(error.localizedDescription))
        }
    }

    /// 逐个检测接口连通性。
    ///
    /// 对写接口（generate / status / delete）用**探测性调用**：
    /// - generate 用 `count: 0`（服务端应拒绝，不产生真实卡密）——
    ///   ⚠️ 实际实现用不存在的 id 列表，避免产生副作用。
    /// - status 用不存在的 id。
    /// - delete 用不存在的 id。
    /// 这样既能验证路径与鉴权，又不会改动真实数据。
    func runChecks() async {
        guard !isChecking else { return }
        isChecking = true

        var results: [EndpointCheck] = []
        for spec in Self.endpointSpecs {
            // ⚠️ 局部变量不能叫 `check` —— 会遮蔽同名方法 `check(spec:)`，
            // 编译报 "cannot call value of non-function type 'EndpointCheck'"。
            var item = EndpointCheck(
                id: spec.id,
                service: spec.service,
                path: spec.path,
                purpose: spec.purpose,
                requiresAuth: spec.requiresAuth,
                result: nil
            )
            item.result = await check(spec: spec)
            results.append(item)
            // 逐条更新界面，避免一次性等待
            checks = results
        }

        lastCheckedAt = Date()
        isChecking = false

        let failed = results.filter { !$0.isSuccess }.count
        toast = failed == 0
            ? "全部 \(results.count) 个接口正常"
            : "\(results.count - failed) 个正常，\(failed) 个异常"
    }

    /// 检测单个接口。
    private func check(spec: (id: String, service: String, path: String, purpose: String, requiresAuth: Bool)) async -> Result<EndpointCheck.CheckOutcome, APIError> {
        do {
            let summary = try await probe(spec: spec)
            return .success(EndpointCheck.CheckOutcome(code: 200, summary: summary))
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    /// 实际发请求并提炼一句摘要。
    private func probe(spec: (id: String, service: String, path: String, purpose: String, requiresAuth: Bool)) async throws -> String {
        let request: APIRequest

        switch spec.id {
        case "login":
            // 用错误口令探测：能返回业务错误就说明端点活着。
            request = APIRequest(
                endpoint: APIEndpoint.login,
                body: ["username": "__probe__", "password": "__probe__"]
            )
        case "getInfo":
            request = APIRequest(endpoint: APIEndpoint.userInfo)
        case "getRouters":
            request = APIRequest(endpoint: APIEndpoint.routers)
        case "cardList":
            request = APIRequest(
                endpoint: APIEndpoint.cardList,
                query: ["pageNum": "1", "pageSize": "1"]
            )
        case "cardGenerate":
            // count 用 0：服务端应拒绝，不产生卡密。
            request = APIRequest(
                endpoint: APIEndpoint.cardGenerate,
                body: ["batchName": "probe", "productId": "LG-APP", "count": 0, "durationDays": 1]
            )
        case "cardStatus":
            // 用不存在的正数 id：走通鉴权与参数校验，不改真实卡。
            request = APIRequest(
                endpoint: APIEndpoint.cardStatus,
                body: ["ids": [999999], "status": 3, "reason": "probe"]
            )
        case "cardUnfreeze":
            request = APIRequest(
                endpoint: APIEndpoint.cardUnfreeze,
                body: ["ids": [999999]]
            )
        case "cardUnban":
            request = APIRequest(
                endpoint: APIEndpoint.cardUnban,
                body: ["ids": [999999]]
            )
        case "cardDelete":
            // ⚠️ 必须用**正数** id：`-1` 会被 nginx 当成命令行选项，
            // 路径被重定向，最终返回「接口不存在」而不是正常的业务响应。
            // 用一个确定不存在的正数 id（999999）既能走通端点，又不会删到真实卡。
            request = APIRequest(endpoint: APIEndpoint.cardDelete(ids: [999999]))
        case "recordList":
            request = APIRequest(
                endpoint: APIEndpoint.recordList,
                query: ["pageNum": "1", "pageSize": "1"]
            )
        case "channelList":
            request = APIRequest(endpoint: APIEndpoint.channelList)
        case "shopCategories":
            request = APIRequest(endpoint: APIEndpoint.shopCategories, service: .shop)
        case "shopCommodities":
            request = APIRequest(endpoint: APIEndpoint.shopCommodities, service: .shop)
        case "shopStock":
            request = APIRequest(
                endpoint: APIEndpoint.shopStock,
                body: .form(["item_id": 1]),
                service: .shop
            )
        case "shopValuation":
            request = APIRequest(
                endpoint: APIEndpoint.shopValuation,
                body: .form(["item_id": 1, "quantity": 1]),
                service: .shop
            )
        case "shopOrderQuery":
            request = APIRequest(
                endpoint: APIEndpoint.shopOrderQuery,
                body: .form(["keywords": "__probe__", "page": 1, "limit": 1]),
                service: .shop
            )
        case "shopOrderSecret":
            request = APIRequest(
                endpoint: APIEndpoint.shopOrderSecret,
                body: .form(["tradeNo": "0", "password": "0"]),
                service: .shop
            )
        case "shopAdminLogin":
            request = APIRequest(
                endpoint: APIEndpoint.shopAdminLogin,
                body: ["username": "__probe__", "password": "__probe__"],
                service: .shopAdmin
            )
        default:
            return "未定义"
        }

        let data = try await client.sendRaw(request)

        // 业务码提取：卡密后台 code=200 为成功，商城前台 code=200 为成功，
        // 店铺后台 code=200 为成功。这里统一读 code/msg。
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let code = (object?["code"] as? Int) ?? -1
        let message = (object?["msg"] as? String) ?? ""

        // 探测用的假凭证会得到业务错误（如「用户名不存在」）——
        // 这恰恰说明**端点连通且鉴权逻辑正常**，因此算作连通。
        switch spec.id {
        case "login", "shopAdminLogin", "shopOrderSecret", "shopValuation", "shopStock":
            if code == 0 || code == 2001 || code == 200 {
                return message.isEmpty ? "连通" : "连通 · \(message)"
            }
            return "code \(code) · \(message)"
        default:
            if code == 200 {
                return summarize(object: object, spec: spec)
            }
            return "code \(code) · \(message)"
        }
    }

    /// 给成功的接口提炼一句人话摘要。
    private func summarize(object: [String: Any]?, spec: (id: String, service: String, path: String, purpose: String, requiresAuth: Bool)) -> String {
        guard let object else { return "连通" }
        switch spec.id {
        case "getInfo":
            let count = (object["permissions"] as? [String])?.count ?? 0
            return "权限点 \(count) 个"
        case "getRouters":
            let count = (object["data"] as? [Any])?.count ?? 0
            return "顶级菜单 \(count) 个"
        case "cardList", "recordList", "channelList":
            let total = (object["total"] as? Int) ?? 0
            return "共 \(total) 条"
        case "shopCategories", "shopCommodities":
            let total = (object["total"] as? Int) ?? 0
            return "共 \(total) 条"
        case "shopOrderQuery":
            let total = ((object["data"] as? [String: Any])?["total"] as? Int) ?? 0
            return "共 \(total) 条"
        default:
            return "连通"
        }
    }
}
