import Foundation
import SwiftUI

// MARK: - 店铺管理 Store

/// 店铺管理的数据源。
///
/// 对应网页版的**商城前台（羁序工坊）**：
/// - 分类（= 店铺 / 商品分组）：`GET /user/api/index/data`
/// - 商品列表：`GET /user/api/index/commodity`
/// - 库存实时查询：`POST /user/api/index/stock`
/// - 价格试算：`POST /user/api/index/valuation`
/// - 订单查询：`POST /user/api/index/query`
/// - 发货内容：`POST /user/api/index/secret`
///
/// ⚠️ 商城的 POST 接口用 **form 编码**（`x-www-form-urlencoded`），不是 JSON。
/// 这是实测踩出来的坑：用 JSON 提交会得到「商品不存在#1」这种误导性错误。
@MainActor
final class ShopStore: ObservableObject {

    // MARK: 分类（店铺）

    @Published private(set) var categories: [ShopCategory] = []
    @Published private(set) var categoryState: LoadState<[ShopCategory]> = .idle

    // MARK: 商品

    @Published private(set) var commodities: [ShopCommodity] = []
    @Published private(set) var commodityState: LoadState<[ShopCommodity]> = .idle
    /// 选中的分类（nil = 全部）。网页版的分类切换行为。
    @Published var selectedCategoryId: Int? {
        didSet {
            guard selectedCategoryId != oldValue else { return }
            Task { await loadCommodities() }
        }
    }

    // MARK: 订单

    @Published private(set) var orders: [ShopOrder] = []
    @Published private(set) var orderTotal: Int = 0
    @Published private(set) var orderState: LoadState<[ShopOrder]> = .idle
    /// 订单查询关键词。
    @Published var orderKeyword: String = ""

    // MARK: 店铺后台会话

    @Published private(set) var shopAdminToken: String? = nil
    @Published private(set) var isLoggingIn = false
    @Published var loginError: String?
    @Published private(set) var shopAdminOverview: ShopAdminOverview?
    @Published private(set) var shopAdminState: LoadState<ShopAdminOverview> = .idle

    @Published var toast: String?

    private let client: APIClient
    private let defaults: UserDefaults
    private let tokenKey = "lg_shop_admin_token"

    init(client: APIClient = .shared, defaults: UserDefaults = .standard) {
        self.client = client
        self.defaults = defaults
        self.shopAdminToken = defaults.string(forKey: tokenKey)
    }

    // MARK: 加载

    /// 首次进入时加载分类与商品。
    func loadIfNeeded() async {
        guard categories.isEmpty, commodities.isEmpty else { return }
        await loadCategories()
        await loadCommodities()
    }

    /// 加载分类（店铺列表）。
    func loadCategories() async {
        categoryState = .loading
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopCategories,
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopListResponse<ShopCategory>.self, from: data)
            guard response.code == 200 else {
                categoryState = .failed(.business(code: response.code, message: response.msg))
                return
            }
            categories = response.data ?? []
            categoryState = .loaded(categories)
        } catch let error as APIError {
            categoryState = .failed(error)
        } catch {
            categoryState = .failed(.transport(error.localizedDescription))
        }
    }

    /// 加载商品（按选中分类过滤）。
    func loadCommodities() async {
        commodityState = .loading
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopCommodities,
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopListResponse<ShopCommodity>.self, from: data)
            guard response.code == 200 else {
                commodityState = .failed(.business(code: response.code, message: response.msg))
                return
            }
            let all = response.data ?? []
            // 网页版是在前端按分类过滤的（`CAT_ID`），这里同样在本地过滤。
            if let categoryId = selectedCategoryId {
                commodities = all.filter { $0.categoryId == categoryId }
            } else {
                commodities = all
            }
            commodityState = .loaded(commodities)
        } catch let error as APIError {
            commodityState = .failed(error)
        } catch {
            commodityState = .failed(.transport(error.localizedDescription))
        }
    }

    /// 查询单个商品的实时库存。
    ///
    /// 网页版在商品详情页调这个接口（`item_ctrl.js` 的 `_GetStock`），
    /// 用 `stock_state <= 0` 判定售罄。
    func queryStock(for commodity: ShopCommodity) async -> ShopStock? {
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopStock,
                body: .form(["item_id": commodity.id]),
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopObjectResponse<ShopStock>.self, from: data)
            guard response.code == 200 else { return nil }
            return response.data
        } catch {
            return nil
        }
    }

    /// 试算商品价格。
    ///
    /// 网页版在商品详情页调这个接口（`item_ctrl.js` 的 `_Abacus`）。
    func queryValuation(itemId: Int, quantity: Int) async -> Double? {
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopValuation,
                body: .form(["item_id": itemId, "quantity": max(1, quantity)]),
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopObjectResponse<ShopPrice>.self, from: data)
            guard response.code == 200 else { return nil }
            return response.data?.price
        } catch {
            return nil
        }
    }

    // MARK: 订单

    /// 查询订单。
    ///
    /// 网页版订单查询页：关键词为「联系方式或订单号」，
    /// 固定 `page: 1, limit: 10`。
    func queryOrders(keyword: String) async {
        let trimmed = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        orderKeyword = trimmed
        orderState = .loading
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopOrderQuery,
                body: .form([
                    "keywords": trimmed,
                    "page": 1,
                    "limit": 10,
                ]),
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopOrderQueryResponse.self, from: data)
            guard response.code == 200 else {
                orderState = .failed(.business(code: response.code, message: response.msg ?? "查询失败"))
                return
            }
            orders = response.data?.list ?? []
            orderTotal = response.data?.total ?? 0
            orderState = .loaded(orders)
        } catch let error as APIError {
            orderState = .failed(error)
        } catch {
            orderState = .failed(.transport(error.localizedDescription))
        }
    }

    /// 读取订单的卡密明文。
    ///
    /// 网页版：需要密码时弹输入框，点「查看卡密」后调这个接口。
    func fetchSecret(tradeNo: String, password: String) async -> Result<ShopOrderSecret, APIError> {
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopOrderSecret,
                body: .form(["tradeNo": tradeNo, "password": password]),
                service: .shop
            ))
            let response = try JSONDecoder().decode(ShopObjectResponse<ShopOrderSecret>.self, from: data)
            guard response.code == 200 else {
                return .failure(.business(code: response.code, message: response.msg ?? "未知错误"))
            }
            guard let payload = response.data else {
                return .failure(.decoding("响应缺少 data"))
            }
            return .success(payload)
        } catch let error as APIError {
            return .failure(error)
        } catch {
            return .failure(.transport(error.localizedDescription))
        }
    }

    // MARK: 店铺后台

    /// 登录店铺后台。
    ///
    /// ⚠️ 文档记录的账号 `3113105903@qq.com / lingyan@2026` 实测已失效
    /// （返回「该邮箱不存在」）。因此这里**不预填任何凭据**，
    /// 由用户自行填写可用的后台账号。
    func login(username: String, password: String) async {
        isLoggingIn = true
        loginError = nil
        defer { isLoggingIn = false }

        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopAdminLogin,
                body: ["username": username, "password": password],
                service: .shopAdmin
            ))
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = (object?["code"] as? Int) ?? -1
            let message = (object?["msg"] as? String) ?? "未知响应"

            // 店铺后台成功码实测是 200（失败是 0）。
            guard code == 200 else {
                loginError = message
                return
            }

            let token = (object?["token"] as? String)
                ?? ((object?["data"] as? [String: Any])?["token"] as? String)
            if let token, !token.isEmpty {
                shopAdminToken = token
                defaults.set(token, forKey: tokenKey)
            }
            await loadShopAdminOverview()
        } catch let error as APIError {
            loginError = error.errorDescription
        } catch {
            loginError = error.localizedDescription
        }
    }

    /// 退出店铺后台登录态。
    func logoutShopAdmin() {
        shopAdminToken = nil
        defaults.removeObject(forKey: tokenKey)
        shopAdminOverview = nil
        shopAdminState = .idle
    }

    /// 拉取店铺后台总览。
    ///
    /// ⚠️ 该接口需要有效的后台会话。账号失效时返回
    /// 「当前页面会话失效，请刷新网页..」，这里如实呈现为失败状态，
    /// 不伪造数据。
    func loadShopAdminOverview() async {
        shopAdminState = .loading
        do {
            let data = try await client.sendRaw(APIRequest(
                endpoint: APIEndpoint.shopAdminDashboardOverview,
                service: .shopAdmin
            ))
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let code = (object?["code"] as? Int) ?? -1
            let message = (object?["msg"] as? String) ?? "未知响应"
            guard code == 200 else {
                shopAdminState = .failed(.business(code: code, message: message))
                return
            }
            let payload = (object?["data"] as? [String: Any]) ?? [:]
            shopAdminOverview = ShopAdminOverview(raw: payload)
            shopAdminState = .loaded(shopAdminOverview!)
        } catch let error as APIError {
            shopAdminState = .failed(error)
        } catch {
            shopAdminState = .failed(.transport(error.localizedDescription))
        }
    }
}

// MARK: - 辅助模型

/// 价格试算结果。
struct ShopPrice: Decodable {
    let price: Double?
}

/// 店铺后台总览。
///
/// ⚠️ 假设说明：接口路径已确认（`GET /admin/api/dashboard/overview`），
/// 但因后台账号失效**未能实测响应结构**。
/// 这里做宽松解析：取到什么显示什么，取不到显示「—」。
struct ShopAdminOverview: Equatable {
    var rawKeys: [String] = []
    var values: [String: String] = [:]

    init(raw: [String: Any]) {
        rawKeys = raw.keys.sorted()
        for (key, value) in raw {
            if let text = value as? String {
                values[key] = text
            } else if let number = value as? NSNumber {
                values[key] = number.stringValue
            }
        }
    }

    /// 是否有可展示的内容。
    var isEmpty: Bool { values.isEmpty }
}
