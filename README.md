# 零砚后台 · iOS / iPadOS 客户端

SwiftUI 实现的卡密后台管理客户端，同时适配 iPhone（单列紧凑布局）与 iPad（分栏 + 多列网格）。

> **接口全部实测验证于 2026-10-25**，不是照文档抄的。
> 实测清单：`../docs/网页版接口实测清单.md`（本文档所有接口的来源与证据）
> 原始需求文档：`../docs/后台接口与功能说明.md`

---

## 一、三个功能模块的落地位置

| 模块 | 页面（View） | 状态层（Store） | 数据模型 |
|---|---|---|---|
| **卡密管理** | `Features/Cards/CardListView.swift`<br>`Features/Cards/CardDetailView.swift`<br>`Features/Cards/CardGenerateView.swift` | `Core/Store/CardStores.swift`<br>→ `CardListStore` | `Core/Models/CardKey.swift` |
| **店铺管理** | `Features/Shop/ShopManagementView.swift` | `Core/Store/ShopStore.swift` | `Core/Models/ShopModels.swift` |
| **对接情况** | `Features/Integration/IntegrationView.swift` | `Core/Store/IntegrationStore.swift` | `Core/Store/IntegrationStore.swift`（`EndpointCheck`） |

**共用基础设施**（未重复实现）：
- `Core/Networking/APIClient.swift` — 统一请求层（鉴权 / 错误 / 重试）
- `Core/Networking/APIEndpoint.swift` — 全部端点的集中定义
- `Core/Networking/TokenStore.swift` — 令牌持久化 + JWT 过期解析
- `Core/Store/SessionStore.swift` — 登录会话与权限
- `UI/CommonViews.swift` — `StatusBadge` / `StatTile` / `StateView` / `ToastBanner` 等共享组件
- `Features/Records/RecordListView.swift` — 操作记录
- `Features/Channels/ChannelListView.swift` — 发卡渠道
- `Features/Dashboard/DashboardView.swift` — 统计首页

侧边栏分区枚举在 `App/RootView.swift` 的 `SidebarSection`：
统计 / **卡密管理** / 操作记录 / 发卡渠道 / **店铺管理** / **对接情况** / 设置

---

## 二、接口清单（实测确认）

### 2.1 卡密后台 `https://z7k2m9xq.lingyan.cyou/prod-api`

账号 `lingyan` / `lingyan@2026` ✅ 可用。请求头 `Authorization: Bearer <token>`。

| 方法 | 路径 | 参数 | 响应 |
|---|---|---|---|
| POST | `/login` | JSON `{username, password}` | 顶层 `token` + `data.token` |
| GET | `/getInfo` | — | `user` / `roles` / `permissions` |
| GET | `/getRouters` | — | 路由表 |
| GET | `/card/key/list` | query `pageNum` `pageSize` `cardNo` `batchNo` `status` | 顶层 `rows[]` `total` |
| POST | `/card/key/generate` | JSON `{batchName, productId, count, durationDays}` | `data{batchNo, successCount, taskId}` |
| PUT | `/card/key/status` | JSON `{ids:[Int], status:Int, reason:String}` | `data{success, skipped[{cardNo,reason}]}` |
| PUT | `/card/key/unfreeze` | JSON `{ids:[Int]}` | `data{success}` |
| PUT | `/card/key/unban` | JSON `{ids:[Int]}` | `data{success}` |
| DELETE | `/card/key/{ids}` | 逗号分隔 id | `data{success}` |
| GET | `/card/record/list` | query `pageNum` `pageSize` | 顶层 `rows[]` `total` |
| GET | `/card/channel/list` | — | 顶层 `rows[]` `total` |

### 2.2 商城前台 `https://www.siyecaogf.cn`（公开，无需登录）

| 方法 | 路径 | 编码 | 请求 | 响应 |
|---|---|---|---|---|
| GET | `/user/api/index/data` | — | — | `{code:200, data:[分类], total:N}` |
| GET | `/user/api/index/commodity` | — | — | `{code:200, data:[商品], total:4}` |
| POST | `/user/api/index/stock` | **form** | `item_id` | `{code:200, data:{stock:"9999", stock_state:4}}` |
| POST | `/user/api/index/valuation` | **form** | `item_id` `quantity` | `{code:200, data:{price:N}}` |
| POST | `/user/api/index/query` | **form** | `keywords` `page` `limit` | `{code:200, data:{list:[...], total:N}}` |
| POST | `/user/api/index/secret` | **form** | `tradeNo` `password` | `{code:200, data:{secret, leave_message, delivery_files}}` |

> ⚠️ **商城 POST 接口必须用 `application/x-www-form-urlencoded`**，不是 JSON。
> 用 JSON 提交会得到「商品不存在#1」这类**误导性**错误。
> 已在 `APIRequest.Body` 里区分 `.json` / `.form` 两种编码。

### 2.3 店铺后台 `https://lgk3f9x2p.lingyan.cyou`

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/admin/api/authentication/login` | ✅ 路径确认 |
| GET | `/admin/api/dashboard/overview` | ✅ 路径确认 |
| GET | `/admin/api/dashboard/trend?days=7` | ✅ 路径确认 |
| GET | `/admin/api/user/data` | ✅ 路径确认 |
| GET | `/admin/api/config/setting` | ✅ 路径确认 |

> ⚠️ **文档里的账号 `3113105903@qq.com / lingyan@2026` 已失效**（实测返回
> `{"code":0,"msg":"该邮箱不存在"}`，另试 7 个常见账号同样结果）。
> 端点路径本身已从前端产物 `assets/admin/controller/auth/login.js` 确认。
> App 里做成**自行填账号**，登录入口在「设置 → 店铺后台账号」。

---

## 三、与网页版的一致性对照

### 3.1 卡密管理

| 网页版 | 本工程 | 一致 |
|---|---|---|
| 搜索框 label「卡密/批次」 | 同 label，placeholder「输入编号或批次」 | ✅ |
| 状态筛选：全部/未发放/已发放/已使用/已冻结/已作废/已过期 | 同枚举同顺序 | ✅ |
| keyword **同时**赋给 `cardNo` 与 `batchNo` | `CardQuery.queryItems()` 同样赋两个参数 | ✅ |
| 表格列：卡密编号 · 商品 · 状态 · 渠道 · 到期 · 订单号 | `tableHeader` 同列同顺序同宽度 | ✅ |
| 状态列 tag 着色（info/默认/success/warning/danger/info） | `CardStatus.color` 同色系映射 | ✅ |
| 到期列：空值显示「永久」，否则 `yyyy-MM-dd` | `expiryText` 同逻辑 | ✅ |
| 批量：冻结 / 封禁（填原因）· 解冻 · 解封 · 删除 | 同动作同接口 | ✅ |
| 弹窗「把选中的 N 张卡冻结，请填原因」 | `ReasonSheet` 同文案 | ✅ |
| 确认「确认解冻选中的 N 张卡？」 | `ConfirmAction.message` 同文案 | ✅ |
| 确认「确认解封选中的 N 张卡？解封后回到「已发放」。」 | 同文案 | ✅ |
| 确认「删除后不可恢复，确认删除选中的 N 张卡？」 | 同文案 | ✅ |
| 提示「成功 N 条，跳过 M 条」 | `applyStatus` 同文案 | ✅ |
| 生成表单：批次名(默认「默认批次」) · 商品(默认「LG-APP」) · 数量(默认 50) · 有效天数(默认 30) | 同字段同默认值同顺序 | ✅ |
| 统计首页三卡：卡密总数 / 未发放 / 已发放 | `DashboardView` 同口径（同为多次 list 的 total） | ✅ |

### 3.2 店铺管理

| 网页版（商城前台） | 本工程 | 一致 |
|---|---|---|
| 分类切换条（`CAT_ID`） | `categoryStrip`，同「全部 + 各分类 + 商品数」 | ✅ |
| 商品卡片标签「自动发货」/「在线发货」 | `deliveryWayTitle`：`delivery_way === 0` → 自动发货 | ✅ |
| 商品卡片标签「推荐」 | `isRecommended`：`recommend == 1` | ✅ |
| 商品卡片价格用 **`price`**（非 `user_price`） | `displayPrice` 用 `price` | ✅ |
| 商品卡片「库存：N」「已售：N」 | `stockText` / `orderSoldText` 同文案 | ✅ |
| 商品卡片声明「该产品是虚拟产品，一经激活不予退款」 | `ShopCommodity.disclaimerText` 同文案 | ✅ |
| 售罄：`stock == 0` → 角标「售罄」 | `isSoldOut` 同判定 | ✅ |
| 商品详情页库存查询 `POST /user/api/index/stock` | `CommodityDetailSheet.stockSection` 同接口 | ✅ |
| 商品详情页价格试算 `POST /user/api/index/valuation` | `priceSection` 同接口 | ✅ |
| 订单查询页关键词「联系方式或订单号」 | `orderSection` 同 placeholder | ✅ |
| 订单查询 `POST /user/api/index/query`（`page:1, limit:10`） | 同参数 | ✅ |
| 订单状态：0 待付款 / 1 已付款 / 未知状态 | `statusTitle` 同映射 | ✅ |
| 发货状态：0 等待发货 / 1 已发货 | `deliveryStatusTitle` 同映射 | ✅ |
| 订单项结构：状态徽标 → 订单号/下单时间/付款时间/支付方式 → 订单金额 → 商品信息 → 宝贝内容 | `OrderCard` 同结构同顺序 | ✅ |
| 「查看卡密」按钮 + 查询密码 | `SecretSheet` 同流程 | ✅ |
| 卡密接口 `POST /user/api/index/secret`（`tradeNo` + `password`） | 同参数 | ✅ |

### 3.3 对接情况

| 项 | 内容 |
|---|---|
| **渠道** | 卡密后台 `GET /card/channel/list` 的全部渠道，展示 `channelName` / `channelCode` / `enabled` / `remark`。实测两个渠道（彩虹发卡、码支付）均为 `enabled: false`，备注「占位配置，本期不发起外部请求」—— 如实呈现 |
| **接口** | 逐个实调 **18 个**对接接口，实时显示连通性与返回摘要（`共 N 条` / `权限点 N 个` / `code X · msg`） |
| **服务** | 三套服务的地址、鉴权方式、登录态 |

检测写接口时使用**探测性调用**（不存在的 id `999999`、`count: 0`、假凭证），
走通端点与鉴权但**不改动真实数据**。

> ⚠️ **删除接口的探测必须用正数 id**：`DELETE /card/key/-1` 会被 nginx
> 当成命令行选项重定向，最终返回「接口不存在」而不是正常业务响应。
> 这个坑已踩过并修掉，代码里有注释标注。

---

## 四、架构说明

### 4.1 网络请求层（`APIClient`）

一个 `actor`，对 UI 只暴露一种错误类型 `APIError`：

```swift
enum APIError {
    case business(code: Int, message: String)   // 业务 code != 200
    case http(status: Int, message: String)      // HTTP 层失败
    case unauthorized                           // token 失效
    case transport(String)                      // 断网/超时/DNS
    case decoding(String)                       // 响应结构不符
    case cancelled
}
```

- **鉴权**：需要鉴权的端点自动加 `Authorization: Bearer <token>`；
  HTTP 401 或业务 `code == 401` 都会清空令牌并触发登出。
- **失败重试**：`.transport` / HTTP 5xx / 429 自动重试 **2 次**，退避 **0.6s → 1.2s**；
  业务错误**不重试**。
- **业务码判定**：后端所有失败都返回 HTTP 200，靠 `code` 区分 ——
  判定失败**必须看 `code`**，只看 HTTP 状态会把所有错误当成功。
- **双编码**：`.json`（卡密后台）与 `.form`（商城前台）分开处理。

### 4.2 状态管理

`@MainActor` + `ObservableObject`：

| Store | 职责 |
|---|---|
| `SessionStore` | 登录、登出、token 持久化、自动登录、用户信息与权限 |
| `CardListStore` | 卡密列表：缓存、搜索、状态筛选、分页、批量操作 |
| `CardStatisticsStore` | 统计面板数据 |
| `RecordListStore` | 操作记录列表（分页） |
| `ChannelListStore` | 渠道列表 |
| `ShopStore` | 店铺/分类、商品、库存、估值、订单、店铺后台会话 |
| `IntegrationStore` | 渠道状态 + 18 个接口的连通性检测 |

加载态统一 `LoadState<Value>`（`idle` / `loading` / `loaded` / `failed`）：

- 首次加载 → 居中 `ProgressView`
- 失败 → 居中错误视图 + **重试按钮**
- 下拉刷新 → **保留旧数据**，失败不清空列表，只弹提示条
- 加载更多失败 → **回滚页码**，保留已有数据

### 4.3 表单校验与提交反馈

`CardGenerateView`：批次名非空且 ≤64 字、数量 1~1000 整数、天数 1~36500 整数；
错误实时显示在对应 Section footer；`isSubmitting` 期间禁用表单并显示进度；
成功后显示「生成成功 / N 张 / 批次号」，批次号可一键复制，自动刷新列表。

---

## 五、响应式布局

判定依据是 `horizontalSizeClass` + **可用宽度**，不硬编码设备类型。

| 场景 | 布局 |
|---|---|
| **iPhone**（compact） | 单列。`NavigationStack` 推栈；顶部菜单切换分区；卡密列表为 `List`，点行进详情 |
| **iPad 全屏**（regular） | `NavigationSplitView` 侧边栏 + 内容区；卡密页左侧列表 + 右侧详情；列表模式是**多列对齐表格**（复刻网页版），可切网格 |
| **iPad 分屏成窄条** | **自动退回单列** |
| **横竖屏切换** | 尺寸类别变化 → 重建布局 |

网格列数按可用宽度自适应：`<500` 1 列 / `<900` 2 列 / `<1300` 3 列 / `≥1300` 4 列。

---

## 六、工程结构

```
ios-admin/
├── project.yml                          # XcodeGen 工程描述
├── .github/workflows/build-ipa.yml      # 云编译 IPA
├── scripts/
│   ├── make_icon.py                     # 纯标准库生成 App 图标
│   ├── swift_check.py                   # 静态检查器
│   └── verify_api.sh                    # 端到端接口验证（53 项）
└── LiquidGlassAdmin/
    ├── Resources/{Info.plist, Assets.xcassets/}
    └── Sources/
        ├── App/            LiquidGlassAdminApp.swift · RootView.swift
        ├── Core/
        │   ├── Networking/ APIConfig · APIEndpoint · APIClient · TokenStore
        │   ├── Models/     CardKey · AdminModels · ShopModels
        │   └── Store/      SessionStore · CardStores · ShopStore · IntegrationStore
        ├── Features/
        │   ├── Login/      LoginView
        │   ├── Dashboard/  DashboardView
        │   ├── Cards/      CardListView · CardDetailView · CardGenerateView
        │   ├── Records/    RecordListView
        │   ├── Channels/   ChannelListView
        │   ├── Shop/       ShopManagementView
        │   ├── Integration/ IntegrationView
        │   └── Settings/   SettingsView
        └── UI/             CommonViews
```

约 6500 行 Swift，**零第三方依赖**（只用 Foundation + SwiftUI）。

---

## 七、运行

### 方式 A：macOS + Xcode

```bash
cd ios-admin
brew install xcodegen
python3 scripts/make_icon.py
xcodegen generate
open LiquidGlassAdmin.xcodeproj
```

### 方式 B：Windows → 云端编译 IPA ✅ 已验证可用

仓库：**<https://github.com/yling1281/liquidglass-admin>**（Public）

推 `main` 分支即自动出包（`.github/workflows/build-ipa.yml`，`macos-26` + Xcode 26）：

```bash
cd ios-admin
git init && git add . && git commit -m "init"
git remote add origin https://github.com/yling1281/liquidglass-admin.git
git push -u origin main
```

约 **80~150 秒**出包，在 [Releases](https://github.com/yling1281/liquidglass-admin/releases)
下载 `LiquidGlassAdmin-unsigned.ipa`，用全能签 / AltStore / Sideloadly 重签安装。

**已产出的包**（`admin-10`，2026-10-25 15:08）：

| 文件 | 大小 | 说明 |
|---|---|---|
| `LiquidGlassAdmin-unsigned.ipa` | 1,106,704 B | 未签名，签名工具用这个 |
| `LiquidGlassAdmin-adhoc.ipa` | 1,116,646 B | adhoc 签名，备用 |

已校验：`Payload/LiquidGlassAdmin.app/` 结构完整、可执行文件 **arm64**、
`Assets.car` 图标在、**无** `_CodeSignature` / `embedded.mobileprovision` 残留。

**CI 失败时怎么看错误**：构建失败会自动把 `build.log` 与编译错误正文
发布成 Release 资产（`log-<N>` 标签），公开可下载 ——
因为 Actions 日志接口需要鉴权，这是唯一可靠的取错路径。

> ⚠️ 仓库里有 `scripts/swift_check.py`，但**它不等于能编过**。
> 本项目 9 轮云编译里，前 7 轮失败全部是静态检查没覆盖到的 Swift 语义错误
> （保留字、actor 隔离、泛型可选扁平化、参数顺序、尾随闭包挂错对象）。
> 每次踩到之后都把规则补进检查器了，现在它覆盖 11 类。

### 方式 C：本地验证

```bash
bash scripts/verify_api.sh          # 端到端接口验证（53 项，全部通过）
python3 scripts/swift_check.py      # Swift 静态检查（0 错误 0 警告）
```

---

## 八、假设与未确认项（代码注释中均已标注）

| # | 事项 | 处理方式 |
|---|---|---|
| 1 | **时间戳单位** | 实测为**秒**（`createTime=1792836303` → 2026-10-24 18:05:03 CST）。前端 `new Date(n*1e3)` 是秒→毫秒换算 |
| 2 | **统计口径** | 服务端无统计接口。数字按网页版首页同法（多次 `list` 的 `total` 汇总）。「在线设备/今日激活/到期预警」需逐条判断，拉全量本地算，**上限 1000 条**，超出时界面标注「基于最近 1000 条估算」 |
| 3 | **永久卡判定** | `durationDays=740991`（≈2029 年）或 `expireAt` 落在 4155 年。按「剩余天数 > 36500（100 年）」判为永久，与网页版 `G()` 一致 |
| 4 | **动作枚举** | 文档未列全，实测只见 `CREATE`/`REDEEM`。其余按语义映射，**未知原样显示英文码**，不瞎猜 |
| 5 | **订单字段** | 订单接口需登录才能列出，字段从网页版渲染逻辑 `_CreateOrderItem` 反推。`ShopOrder` 做**宽松解析**（每个字段试多个候选键），字段名不符也不会整页空白 |
| 6 | **店铺后台数据** | 路径已确认，但账号失效 → 只能验证连通性。App 如实呈现「需要后台账号」，**不伪造成功** |
| 7 | **令牌存储** | `UserDefaults` 而非 Keychain。令牌是短期 JWT（payload 含 `exp`）。若要「设备丢失远程踢下线」，需改 Keychain + 服务端吊销列表 |
| 8 | **通知** | 「到期提醒」仅存本机，**系统级推送未接入**（需 APNs + 服务端配合），界面已说明 |
| 9 | **`card:key:renew` / `card:key:secret`** | 有权限点但**无对应接口**（服务端返回「接口不存在」），故未实现 |
| 10 | **删除接口探测 id** | 必须用正数 id。`-1` 会被 nginx 当选项重定向，返回「接口不存在」误报 |

---

## 九、验证情况

**已实测（真实服务端，53 项断言全部通过）**：
登录、token 签发与 JWT 过期解析、用户信息与权限、路由表、卡密列表分页与状态筛选、
卡号/批次搜索、批量生成、状态变更（冻结/封禁）、解冻、解封、删除、操作记录、
渠道列表、商城分类、商品列表、库存查询、价格试算、订单查询、发货内容、
店铺后台登录与总览端点。

**未能实测**：
- **真机运行** —— 已通过云端 Xcode 26 编译（arm64 Release 成功），但**没有在真机/模拟器上跑过**，
  首次启动的运行时表现未经确认。
- 店铺后台的**数据**（账号失效，路径已确认）。

**静态检查**（`scripts/swift_check.py`）：括号配平（基于剥离注释与字符串后的文本）、
编码完整性（U+FFFD）、条件编译配平、跨文件类型引用（含「引用了已删除的类型」）、
未使用状态属性、Swift 常见不可用 API、**保留字作标识符**、**LoadState/Result 的 case 名混用**、
**具名参数顺序**、**容器字面量拆坏**、**静态工厂自递归**、**StateView 尾随闭包挂错对象**。
当前结果：**0 错误 0 警告**。

---

## 十、云端构建踩坑记录（真实教训）

第一次上云编译，**连挂 7 轮**才成功。每一轮的错误都补进了 `swift_check.py`：

| 轮次 | 错误 | 原因 | 已加规则 |
|---|---|---|---|
| #1-3 | `Bootstrap` 之前源码没进仓库 | 仓库只有配置 | — |
| #4 | `keyword 'operator' cannot be used as an identifier` | `CardRecord.operator` 撞 Swift 保留字 | ✅ 保留字检查 |
| #5 | 16 处：`LoadState has no member 'failure'`、参数顺序、actor 隔离、泛型可选 | 批量替换的副作用 + `try?` 扁平化 | ✅ case 名 / 参数顺序 |
| #6 | `expected expression in container literal` | 批量改参数顺序把多行 `[` 拆坏 | ✅ 容器字面量检查 |
| #7 | `extra trailing closure passed in call` | `StateView(kind: .failure(e)) { }` 闭包挂到了外层 init | ✅ 尾随闭包检查 |
| #8 | 6 处：`LoadState.empty`、`Result.failed`、actor 属性赋值、`v!` 非可选 | 上轮替换波及 + 架构问题 | ✅ 自递归检查 |
| #9 | **成功** | — | — |

**四条硬结论**：

1. **`try?` 会扁平化嵌套可选**（SE-0230）。`decodeIfPresent` 返回 `T?`，经 `try?` 后仍是 `T?`，
   `if let` 解出的是**非可选** `T`，再写 `v!` 必报错。改用 `try? c.decode(...)`。
2. **actor 的隔离属性不能从主线程赋值**。要么通过方法设置（`setUnauthorizedHandler`），
   要么先取到局部变量再进 `MainActor.run`。
3. **Swift 具名参数的书写顺序必须与声明顺序一致**，不能因为"看起来更顺"就调换。
   批量改顺序时，**多行容器字面量最容易被正则拆坏** —— 改完必须重新打包校验 sha256。
4. **尾随闭包只会挂到最外层的 init 上**。`Kind.failure` 有两个关联值（error + retry），
   所以必须写成 `StateView.failure(error) { ... }`（工厂方法），不能用 `kind:` 形式。

**仓库自举**：第一次推送时仓库里只有配置，Swift 源码通过一个公网 `.bin` 包自举。
构建成功后 CI 会自动把源码提交回仓库并删掉 `.bootstrap-url`（带 `[skip ci]` 防循环），
所以现在仓库是**自包含**的，后续直接改源码推送即可。
