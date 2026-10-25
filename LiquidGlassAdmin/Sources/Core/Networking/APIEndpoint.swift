import Foundation

// MARK: - HTTP 方法

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

// MARK: - 端点定义

/// 后台全部接口的集中定义。
///
/// **全部路径均为实测验证**（2026-10-25），来源：
/// - 前端产物 `static/js/card-CaCNzl4f.js` 的 API 模块；
/// - 服务端 `GET /getRouters` 路由表；
/// - 逐个接口 curl 实调确认请求体与响应结构。
enum APIEndpoint {

    // MARK: 鉴权

    /// 登录。`POST /login`，body: `{username, password}`。
    /// 响应：顶层 `token` + `data.token`。
    static let login = Endpoint(
        path: "/login",
        method: .post,
        requiresAuth: false
    )

    /// 当前登录用户信息 + 权限点。`GET /getInfo`。
    static let userInfo = Endpoint(path: "/getInfo", method: .get)

    /// 动态路由表。`GET /getRouters`。
    static let routers = Endpoint(path: "/getRouters", method: .get)

    // MARK: QQ 第三方登录

    /// 当前账号的 QQ 绑定状态。`GET /qq/status`（需登录）
    /// 响应 `data`: `{bound, nickname, figureurl, openidMasked, isAdmin, configured}`
    static let qqStatus = Endpoint(path: "/qq/status", method: .get)

    /// 取一次性绑定票据。`POST /qq/bind/ticket`（需登录 + 管理员）
    /// 响应 `data`: `{ticket, url}`，`url` 是 `/qq/authorize?t=…` 相对路径。
    static let qqBindTicket = Endpoint(path: "/qq/bind/ticket", method: .post)

    /// 解绑 QQ。`POST /qq/unbind`（需登录 + 管理员）
    static let qqUnbind = Endpoint(path: "/qq/unbind", method: .post)

    // MARK: 卡密

    /// 卡密列表。`GET /card/key/list`
    /// query: `pageNum` / `pageSize` / `cardNo` / `batchNo` / `status`
    /// 响应：顶层 `rows` / `total` / `pageNum` / `pageSize`。
    static let cardList = Endpoint(path: "/card/key/list", method: .get)

    /// 批量生成卡密。`POST /card/key/generate`
    /// body: `{batchName, productId, count, durationDays}`
    /// 响应 `data`: `{batchNo, successCount, taskId}`
    static let cardGenerate = Endpoint(path: "/card/key/generate", method: .post)

    /// 修改卡密状态。`PUT /card/key/status`
    /// body: `{ids: [Int], status: Int, reason: String}`
    /// 响应 `data`: `{success: Int, skipped: [String]}`
    static let cardStatus = Endpoint(path: "/card/key/status", method: .put)

    /// 解冻卡密。`PUT /card/key/unfreeze` body: `{ids: [Int]}` → `data.success`
    static let cardUnfreeze = Endpoint(path: "/card/key/unfreeze", method: .put)

    /// 解封卡密。`PUT /card/key/unban` body: `{ids: [Int]}` → `data.success`
    static let cardUnban = Endpoint(path: "/card/key/unban", method: .put)

    /// 删除卡密。`DELETE /card/key/{ids}`，ids 为逗号分隔的数字 id。
    /// 响应 `data`: `{success: Int}`
    static func cardDelete(ids: [Int]) -> Endpoint {
        Endpoint(
            path: "/card/key/" + ids.map(String.init).joined(separator: ","),
            method: .delete
        )
    }

    // MARK: 操作记录

    /// 卡密操作记录。`GET /card/record/list`
    static let recordList = Endpoint(path: "/card/record/list", method: .get)

    // MARK: 渠道

    /// 发卡渠道列表。`GET /card/channel/list` → 顶层 `rows` / `total`。
    static let channelList = Endpoint(path: "/card/channel/list", method: .get)

    // MARK: 商城前台

    /// 商城商品分类（= 店铺/商品分组）。`GET /user/api/index/data`
    static let shopCategories = Endpoint(path: "/user/api/index/data", method: .get, requiresAuth: false)

    /// 商城商品列表。`GET /user/api/index/commodity`
    static let shopCommodities = Endpoint(path: "/user/api/index/commodity", method: .get, requiresAuth: false)

    /// 商品库存查询。`POST /user/api/index/stock`（**form 编码**）
    static let shopStock = Endpoint(path: "/user/api/index/stock", method: .post, requiresAuth: false)

    /// 商品价格试算。`POST /user/api/index/valuation`（**form 编码**）
    static let shopValuation = Endpoint(path: "/user/api/index/valuation", method: .post, requiresAuth: false)

    /// 订单查询。`POST /user/api/index/query`（**form 编码**）
    static let shopOrderQuery = Endpoint(path: "/user/api/index/query", method: .post, requiresAuth: false)

    /// 订单发货内容（卡密明文）。`POST /user/api/index/secret`（**form 编码**）
    static let shopOrderSecret = Endpoint(path: "/user/api/index/secret", method: .post, requiresAuth: false)

    // MARK: 店铺后台

    /// 店铺后台登录。`POST /admin/api/authentication/login`
    ///
    /// ⚠️ 实测 2026-10-25 用文档里的账号返回 `{"code":0,"msg":"该邮箱不存在"}`。
    /// 端点本身已从前端产物 `assets/admin/controller/auth/login.js` 确认为真实路径。
    static let shopAdminLogin = Endpoint(
        path: "/admin/api/authentication/login",
        method: .post,
        requiresAuth: false
    )

    /// 店铺后台总览。`GET /admin/api/dashboard/overview`
    static let shopAdminDashboardOverview = Endpoint(
        path: "/admin/api/dashboard/overview",
        method: .get,
        requiresAuth: false
    )

    /// 店铺后台趋势。`GET /admin/api/dashboard/trend?days=7`
    static let shopAdminDashboardTrend = Endpoint(
        path: "/admin/api/dashboard/trend",
        method: .get,
        requiresAuth: false
    )

    /// 店铺后台用户列表。`GET /admin/api/user/data`
    static let shopAdminUserData = Endpoint(
        path: "/admin/api/user/data",
        method: .get,
        requiresAuth: false
    )

    /// 店铺后台站点设置。`GET /admin/api/config/setting`
    static let shopAdminConfigSetting = Endpoint(
        path: "/admin/api/config/setting",
        method: .get,
        requiresAuth: false
    )
}

// MARK: - 端点结构

/// 单个 API 端点的描述。
struct Endpoint {
    let path: String
    let method: HTTPMethod
    /// 是否需要带 `Authorization: Bearer <token>`。
    var requiresAuth: Bool = true
    /// body 是否用 JSON 编码（GET 用 query，DELETE 不带 body）。
    var encodesBodyAsJSON: Bool = true

    init(
        path: String,
        method: HTTPMethod,
        requiresAuth: Bool = true,
        encodesBodyAsJSON: Bool = true
    ) {
        self.path = path
        self.method = method
        self.requiresAuth = requiresAuth
        self.encodesBodyAsJSON = encodesBodyAsJSON
    }
}
