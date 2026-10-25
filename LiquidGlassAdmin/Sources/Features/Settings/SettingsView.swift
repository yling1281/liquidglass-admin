import SwiftUI

// MARK: - 设置页

/// 设置页。
///
/// 内容：
/// - 账号信息（用户名、昵称、权限点）。
/// - QQ 登录绑定（仅管理员）。
/// - 店铺后台账号。
/// - 服务器地址（三套），可改可重置。
/// - 通知开关（本地偏好，实际推送未接入）。
/// - 退出登录。
struct SettingsView: View {

    @ObservedObject var session: SessionStore
    @ObservedObject var shopStore: ShopStore

    @Environment(\.horizontalSizeClass) private var hSizeClass
    @State private var draft = ServerConfig.default
    @State private var showingResetAlert = false
    @State private var savedHint: String?
    @State private var expiryReminderEnabled = true
    @State private var expiryReminderDays = 7
    @State private var shopAdminUsername = ""
    @State private var shopAdminPassword = ""

    // QQ 绑定
    @State private var qqBinding: SessionStore.QQBinding?
    @State private var isQQBusy = false
    @State private var qqMessage: String?
    @State private var qqMessageIsError = false
    private let qqAuth = QQAuthSession.shared

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        Form {
            accountSection
            qqSection
            shopAdminSection
            serverSection
            notificationSection
            aboutSection
            logoutSection
        }
        .navigationTitle("设置")
        .onAppear {
            draft = ServerConfigStore.shared.config
        }
    }

    // MARK: 账号

    private var accountSection: some View {
        Section("账号") {
            if let user = session.user {
                LabeledContent("用户名", value: user.userName)
                LabeledContent("昵称", value: user.displayName)
                if !user.roles.isEmpty {
                    LabeledContent("角色", value: user.roles.joined(separator: ", "))
                }
            } else {
                LabeledContent("用户名", value: "—")
            }

            if !session.permissions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("权限点（\(session.permissions.count)）")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    FlowLayout(spacing: 6) {
                        ForEach(session.permissions, id: \.self) { permission in
                            Text(permission)
                                .font(.caption2.monospaced())
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
        }
    }

    // MARK: QQ 登录

    private var qqSection: some View {
        Section {
            if let binding = qqBinding {
                if binding.bound {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.title3)
                            .foregroundStyle(Color(red: 0.07, green: 0.72, blue: 0.96))

                        VStack(alignment: .leading, spacing: 2) {
                            Text(binding.nickname.isEmpty ? "已绑定 QQ" : binding.nickname)
                                .font(.subheadline.weight(.medium))
                            Text("openid \(binding.openidMasked)")
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("解绑", role: .destructive) {
                            unbindQQ()
                        }
                        .font(.caption)
                        .disabled(isQQBusy)
                    }
                } else {
                    HStack {
                        Label("未绑定 QQ", systemImage: "qrcode")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(isQQBusy ? "绑定中…" : "绑定 QQ") {
                            bindQQ()
                        }
                        .font(.caption)
                        .disabled(isQQBusy || !binding.configured || !binding.isAdmin)
                    }
                }

                if !binding.configured {
                    Label("服务器还没配置 QQ 登录（缺 qq_config.json）",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                } else if !binding.isAdmin {
                    Label("只有管理员可以绑定 QQ", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取 QQ 绑定状态…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let qqMessage {
                Label(qqMessage, systemImage: qqMessageIsError
                      ? "exclamationmark.triangle.fill"
                      : "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(qqMessageIsError ? Color.red : Color.green)
            }
        } header: {
            Text("QQ 登录")
        } footer: {
            Text("绑定后可以在登录页用「QQ 授权登录」一键进入后台，不用每次输密码。绑定关系存在服务器上，换手机也有效。")
        }
        .task {
            await reloadQQStatus()
        }
    }

    private func reloadQQStatus() async {
        qqBinding = await session.loadQQStatus()
    }

    private func bindQQ() {
        guard !isQQBusy else { return }
        qqMessage = nil
        isQQBusy = true

        Task {
            defer { isQQBusy = false }
            switch await session.requestQQBindURL() {
            case .failure(let error):
                qqMessage = error.errorDescription
                qqMessageIsError = true
            case .success(let url):
                do {
                    let payload = try await qqAuth.authenticate(url: url)
                    if payload.isBind {
                        qqMessage = "绑定成功"
                        qqMessageIsError = false
                    } else if let message = payload.errorMessage {
                        qqMessage = message
                        qqMessageIsError = true
                    } else {
                        qqMessage = "绑定没有完成"
                        qqMessageIsError = true
                    }
                } catch {
                    qqMessage = error.localizedDescription
                    qqMessageIsError = true
                }
                await reloadQQStatus()
            }
        }
    }

    private func unbindQQ() {
        guard !isQQBusy else { return }
        qqMessage = nil
        isQQBusy = true

        Task {
            defer { isQQBusy = false }
            if let error = await session.unbindQQ() {
                qqMessage = error
                qqMessageIsError = true
            } else {
                qqMessage = "已解绑"
                qqMessageIsError = false
            }
            await reloadQQStatus()
        }
    }

    // MARK: 店铺后台账号

    private var shopAdminSection: some View {
        Section {
            if shopStore.shopAdminToken != nil {
                HStack {
                    Label("已登录店铺后台", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                    Spacer()
                    Button("退出") {
                        shopStore.logoutShopAdmin()
                    }
                    .font(.caption)
                }
            } else {
                TextField("邮箱", text: $shopAdminUsername)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.emailAddress)

                SecureField("密码", text: $shopAdminPassword)

                Button {
                    Task {
                        await shopStore.login(
                            username: shopAdminUsername.trimmingCharacters(in: .whitespaces),
                            password: shopAdminPassword
                        )
                        if shopStore.loginError == nil {
                            shopAdminPassword = ""
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        if shopStore.isLoggingIn {
                            ProgressView().controlSize(.small)
                        }
                        Text(shopStore.isLoggingIn ? "登录中…" : "登录店铺后台")
                    }
                }
                .disabled(
                    shopAdminUsername.isEmpty
                    || shopAdminPassword.isEmpty
                    || shopStore.isLoggingIn
                )
            }

            if let error = shopStore.loginError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("店铺后台账号")
        } footer: {
            Text("店铺后台与卡密后台是两套独立账号。文档中记录的账号已返回「该邮箱不存在」，请填入可用的后台账号。店铺管理页的商品与店铺数据走商城前台公开接口，无需登录即可查看。")
        }
    }

    // MARK: 服务器

    private var serverSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("卡密后台 API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://…/prod-api", text: $draft.cardAPIBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("商城前台 API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://…", text: $draft.shopAPIBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("店铺后台 API")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("https://…", text: $draft.shopAdminAPIBase)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(.footnote.monospaced())
            }

            Button {
                ServerConfigStore.shared.config = draft
                savedHint = "服务器地址已保存"
            } label: {
                Label("保存服务器地址", systemImage: "checkmark.circle")
            }

            Button(role: .destructive) {
                showingResetAlert = true
            } label: {
                Label("恢复默认地址", systemImage: "arrow.counterclockwise")
            }
        } header: {
            Text("服务器地址")
        } footer: {
            if let savedHint {
                Text(savedHint)
                    .foregroundStyle(.green)
            } else {
                Text("修改后需重新登录才能生效（新地址下旧的 token 无效）。")
            }
        }
        .alert("恢复默认地址？", isPresented: $showingResetAlert) {
            Button("取消", role: .cancel) {}
            Button("恢复", role: .destructive) {
                ServerConfigStore.shared.resetToDefault()
                draft = .default
                savedHint = "已恢复默认地址"
            }
        }
    }

    // MARK: 通知

    private var notificationSection: some View {
        Section {
            Toggle("到期提醒", isOn: $expiryReminderEnabled)
            if expiryReminderEnabled {
                Stepper(
                    "提前 \(expiryReminderDays) 天提醒",
                    value: $expiryReminderDays,
                    in: 1...30
                )
            }
        } header: {
            Text("通知")
        } footer: {
            Text("⚠️ 提醒偏好目前仅保存在本机；系统级推送通知尚未接入（需要 APNs 与服务端配合）。")
        }
    }

    // MARK: 关于

    private var aboutSection: some View {
        Section("关于") {
            LabeledContent("版本", value: Bundle.main.appVersion)
            Link(destination: URL(string: AppConfig.defaultCardAdminWeb)!) {
                Label("打开网页版卡密后台", systemImage: "safari")
            }
            Link(destination: URL(string: AppConfig.defaultShopWeb)!) {
                Label("打开商城前台", systemImage: "bag")
            }
        }
    }

    // MARK: 退出

    private var logoutSection: some View {
        Section {
            Button(role: .destructive) {
                session.logout()
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}

// MARK: - 流式布局

/// 自动换行的横向布局（用于权限点标签）。
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > maxWidth {
                totalHeight += rowHeight + spacing
                x = 0
                y = totalHeight
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        totalHeight += rowHeight
        return CGSize(width: proposal.width ?? x, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: ProposedViewSize(size)
            )
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - 版本号

extension Bundle {
    /// 展示用版本号（`1.0.0 (1)`）。
    var appVersion: String {
        let short = infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "—"
        return "\(short) (\(build))"
    }
}
