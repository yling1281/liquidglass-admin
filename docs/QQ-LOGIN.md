# QQ 第三方登录（管理员专用）

> 落地时间：2026-10-25
> 涉及：卡密后台服务端（`38.76.168.61:/opt/cardkey`）、网页版登录页、iOS 客户端

---

## 一、需求

- 管理后台可以在**设置里绑定 QQ**，绑定之后**用 QQ 授权一键登录**。
- **只有管理员**能用；只读账号（`viewer`）一律拒绝。

---

## 二、总体流程

三条流程共用一个回调地址 `https://z7k2m9xq.lingyan.cyou/prod-api/qq/callback`
（QQ 互联应用 `1905772658` 登记的就是它）。

```
① App 登录
   App  ──打开──▶ /qq/authorize?mode=app
                    │ 302
                    ▼
              graph.qq.com/oauth2.0/authorize
                    │ 用户授权
                    ▼
              /qq/callback?code&state
                    │ 换 openid → 查 sys_user_qq → token_for() 签 JWT
                    ▼
              lingyankey://login?token=<卡密 JWT>   ← App 接住并落库

② 网页登录
   /login 页「QQ 登录」──▶ /qq/authorize?mode=web ──▶ QQ ──▶ /qq/callback
                    │ 302
                    ▼
              /qq/done?token=…   写 Admin-Token cookie 后跳 /

③ 绑定（已登录的管理员）
   设置页「绑定 QQ」──POST /qq/bind/ticket（Bearer）──▶ {ticket, url}
                    │ 打开 url
                    ▼
              /qq/authorize?t=<ticket>   ← 打开即作废，换发新票
                    │ 302
                    ▼
              QQ ──▶ /qq/callback ──▶ 写 sys_user_qq ──▶ lingyankey://bind?ok=1
```

---

## 三、服务端改动

文件：`/opt/cardkey/server.py`（线上 1248 行 → 补丁后 1641 行）
补丁脚本：`F:\mc\_deploy\patch_qq.py`（锚点断言 + AST 语法检查）
部署脚本：`F:\mc\_deploy\deploy_qq.py`（自动备份 → 上传 → py_compile → 重启）

### 3.1 新增两张表

```sql
CREATE TABLE IF NOT EXISTS sys_user_qq(
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id INTEGER UNIQUE,     -- 一个管理员只绑一个 QQ
  openid TEXT UNIQUE,         -- 一个 QQ 只能绑一个管理员
  nickname TEXT, figureurl TEXT, unionid TEXT, bind_time INTEGER
);
CREATE TABLE IF NOT EXISTS qq_ticket(
  ticket TEXT PRIMARY KEY, user_id INTEGER, mode TEXT, create_time INTEGER
);
```

### 3.2 新增接口

| 方法 | 路径 | 鉴权 | 说明 |
|---|---|---|---|
| GET | `/qq/authorize` | 否 | `?mode=app|web` 或 `?t=<票据>`，302 到腾讯 |
| GET | `/qq/callback` | 否 | 换 openid、查绑定、签发 token / 回绑成功 |
| GET | `/qq/done` | 否 | 网页版落地页：写 `Admin-Token` cookie 后跳 `/` |
| GET | `/qq/status` | 是 | `{bound, nickname, figureurl, openidMasked, isAdmin, configured}` |
| POST | `/qq/bind/ticket` | 是 + 管理员 | 发一次性绑定票据 `{ticket, url}` |
| POST | `/qq/unbind` | 是 + 管理员 | 解绑 |

### 3.3 配置

`/opt/cardkey/qq_config.json`（600，root）—— **AppKey 只存在这里，任何响应都不回显**：

```json
{ "appid": "1905772658", "appkey": "<QQ 互联 APP Key>",
  "redirect": "https://z7k2m9xq.lingyan.cyou/prod-api/qq/callback" }
```

生成方式：`deploy_qq.py` 在服务器上从 `/opt/fla-sync/.env` 读出
`FLA_QQ_APPID` / `FLA_QQ_APPKEY` 直接写入，**密钥不经过本地也不进日志**。

### 3.4 三个安全设计（都踩过坑）

1. **票据一次性 + 打开即轮换**
   最初 `/qq/authorize?t=` 只查票不消费，于是同一个绑定链接能反复打开 ——
   链接一旦泄露（浏览器历史、聊天记录），别人打开后授权**他自己的 QQ**，
   就把他的 QQ 绑到了管理员账号上，之后能直接登后台。
   现在一进 `/qq/authorize` 就消费旧票、换发同归属的新票给 `state`，
   旧链接立刻作废。绑定票 TTL 也从 900s 收紧到 **300s**。

2. **管理员闸门用「写权限」判定**
   不看用户名是不是 `admin`（线上实际管理员叫 `lingyan`），
   而是看 `perms` 里有没有 `card:key:status`。`viewer` 只有 `list/record`，
   自动被挡在门外。实测返回 `{"code":403,"msg":"只有管理员可以绑定 QQ"}`。

3. **openid 对外只给前 8 位掩码**，完整值不出服务端。

### 3.5 顺带修的 SPA 深链问题

前端是若依单页应用，页面路由（`/login`、`/index`）在服务端没有对应文件，
未登录直接刷新 `/login` 会掉进兜底的 `_need()` 返回 **401 JSON**（实测截图确认）。
现在对 `/login` `/index` `/register` `/404` `/401` 做 index.html 回退，
API 路径不受影响。

---

## 四、网页版改动

前端是若依编译产物，仓库里没有登录页源码，所以**不改编译产物**，
改用运行时注入：

- `/opt/cardkey/web/qq-login.js` —— 检测到页面出现密码输入框（即登录页）时，
  在表单下方插入「或 / QQ 登录」按钮，跳 `/prod-api/qq/authorize?mode=web`。
- `/opt/cardkey/web/index.html` 末尾加一行 `<script src="/qq-login.js"></script>`。

好处：升级若依前端不会冲掉这个按钮。

---

## 五、iOS 改动

| 文件 | 改了什么 |
|---|---|
| `Resources/Info.plist` | 注册 URL Scheme `lingyankey` |
| `Core/Networking/QQAuth.swift`（新增） | `ASWebAuthenticationSession` 封装 + 回调解析 |
| `Core/Networking/APIEndpoint.swift` | 新增 `qqStatus` / `qqBindTicket` / `qqUnbind` |
| `Core/Store/SessionStore.swift` | `loginWithQQToken` / `loadQQStatus` / `requestQQBindURL` / `unbindQQ` |
| `Features/Login/LoginView.swift` | 布局重写 + QQ 登录按钮 + 邮箱误用提示 |
| `Features/Settings/SettingsView.swift` | 新增「QQ 登录」绑定/解绑区 |

### 5.1 登录页布局修复

上一版的三个实际缺陷：

1. **内容贴顶**，下半屏空一大片 —— 内容在 `ScrollView` 里按自然高度排，
   没有撑满一屏。现在包在 `GeometryReader` 里，用
   `.frame(minHeight: geo.size.height)` 撑满，自然垂直居中，键盘弹出仍可滚动。
2. **图标压住占位文字** —— 原来的写法是
   `TextField.padding(12).background(...).overlay(图标).padding(.leading, 28)`，
   图标和文字都从 x=12 开始，互相重叠；而 `.padding(.leading, 28)` 又把
   **背景**推歪了 28pt。现在改成 `HStack(图标 + 输入)` 一个整体套底色。
3. **密码框看不到占位文字** —— 同一个根因，已随之修复。

### 5.2 登录失败提示

用邮箱登会返回 `用户不存在/密码错误`（服务端只认 `user_name`），
现在除了原错误，再补一条蓝色提示：

> 提示：卡密后台用「用户名」登录（账号是 lingyan），不是邮箱。

### 5.3 为什么用 `ASWebAuthenticationSession`

- 系统弹窗能直接拦截 `lingyankey://` 回调，不用配 Universal Link；
- 用户看得到地址栏，确认是在给 `graph.qq.com` 授权；
- `prefersEphemeralWebBrowserSession = false` 复用 Safari Cookie，
  QQ 已登录时一次点完。

⚠️ 会话对象必须用 `QQAuthSession.shared`（单例）。写成 View 里的
`private let qqAuth = QQAuthSession()` 会因为 SwiftUI 重建 View 而提前释放，
表现为「点了 QQ 登录一直转圈，回调永远不回来」。

---

## 六、验证

```bash
bash scripts/verify_api.sh   # 64 项，全部通过（含 11 项 QQ 断言）
```

覆盖：`/qq/status` 字段、发票据、302 到腾讯、回调地址正确、
**票据二次打开被拒**、`mode=web/app` 两种入口、`/login` SPA 回退、`/qq-login.js` 可访问。

手工验证过的：

- QQ 授权页能正常打开（返回 `QQ帐号安全登录` 登录页，说明回调地址已被腾讯接受）
- `viewer` 取票据被拒（403）
- 网页版登录页截图确认「或 / QQ 登录」按钮已渲染
- IPA 里能查到 `lingyankey` scheme、`QQ 授权登录` 文案、`openidMasked` 字段

**未验证**：真实 QQ 账号走完整授权（需要你的 QQ 扫码/输密码），
以及 iOS 真机的 `ASWebAuthenticationSession` 弹窗表现。

---

## 七、回滚

```bash
ssh root@38.76.168.61
systemctl stop cardkey
cp /opt/cardkey/server.py.bak-<时间戳> /opt/cardkey/server.py
systemctl start cardkey
```

备份在 `/opt/cardkey/server.py.bak-20261025-1642xx` / `-1646xx` / `-1652xx`。
`qq_config.json` 和两张新表留着不影响老逻辑（没有 DROP）。
