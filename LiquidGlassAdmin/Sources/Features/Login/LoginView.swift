import SwiftUI

// MARK: - 登录页

/// 登录页。
///
/// 两种登录方式：
/// 1. **账号密码** —— 卡密后台的用户名（`lingyan`），**不是邮箱**。
///    用邮箱登会返回「用户不存在/密码错误」，所以这里会额外补一句提示。
/// 2. **QQ 授权** —— 先走账号密码登录，到「设置 → QQ 登录」绑定；
///    之后就能一键授权进后台。只有管理员能绑定（服务端按写权限校验）。
///
/// 布局要点（上一版的问题都在这里修掉）：
/// - 内容包在 `GeometryReader` + `minHeight` 里，**垂直居中**，不再贴顶留一大片空白。
/// - 输入框用 `HStack(图标 + 输入)` 一个整体做底色，图标不会压住占位文字，
///   也不会出现「背景被 leading padding 推歪」的错位。
struct LoginView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var username: String = AppConfig.defaultUsername
    @State private var password: String = ""
    @State private var isSubmitting = false

    // QQ 登录
    @State private var isQQWorking = false
    @State private var qqError: String?
    private let qqAuth = QQAuthSession.shared

    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 26) {
                    header
                    formCard
                    feedback
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                // 关键：撑满可视高度 → 内容在屏幕中垂直居中；键盘弹出时又能滚动
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(backgroundGradient)
        }
        .animation(.easeInOut(duration: 0.18), value: session.loginError != nil)
        .animation(.easeInOut(duration: 0.18), value: qqError != nil)
    }

    // MARK: 背景

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: 标题

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 52))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)

            Text("零砚后台")
                .font(.largeTitle.weight(.bold))

            Text("卡密中心 · 登录")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: 表单

    private var formCard: some View {
        VStack(spacing: 14) {
            inputRow(
                systemImage: "person",
                placeholder: "用户名",
                text: $username,
                field: .username,
                isSecure: false
            )

            inputRow(
                systemImage: "key",
                placeholder: "密码",
                text: $password,
                field: .password,
                isSecure: true
            )

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    }
                    Text(isSubmitting ? "登录中…" : "登录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || isQQWorking || username.isEmpty || password.isEmpty)

            // 分隔 + QQ 登录
            HStack(spacing: 10) {
                Rectangle().fill(Color.secondary.opacity(0.22)).frame(height: 1)
                Text("或")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Rectangle().fill(Color.secondary.opacity(0.22)).frame(height: 1)
            }
            .padding(.top, 2)

            Button(action: submitQQ) {
                HStack(spacing: 8) {
                    if isQQWorking {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white)
                    } else {
                        Image(systemName: "qrcode")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    Text(isQQWorking ? "正在打开 QQ…" : "QQ 授权登录")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .foregroundStyle(.white)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.07, green: 0.72, blue: 0.96))
                )
            }
            .buttonStyle(.plain)
            .disabled(isSubmitting || isQQWorking)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    /// 一行输入框：图标与输入区在同一个 `HStack` 里，底色包住整体。
    private func inputRow(
        systemImage: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: text)
                        .textContentType(.password)
                } else {
                    TextField(placeholder, text: text)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .textFieldStyle(.plain)
            .focused($focusedField, equals: field)
            .submitLabel(field == .username ? .next : .go)
            .onSubmit {
                if field == .username {
                    focusedField = .password
                } else {
                    submit()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .accessibilityLabel(placeholder)
    }

    // MARK: 提示

    @ViewBuilder
    private var feedback: some View {
        if let message = qqError {
            notice(message, color: .red, icon: "exclamationmark.triangle.fill")
        }
        if let error = session.loginError {
            VStack(spacing: 8) {
                notice(error.errorDescription ?? "登录失败",
                       color: .orange,
                       icon: "exclamationmark.triangle.fill")

                // 用邮箱登会报「用户不存在/密码错误」，但真实原因是这个后台只认用户名。
                if case .business(_, let msg) = error,
                   msg.contains("用户不存在") || msg.contains("密码错误") {
                    notice("提示：卡密后台用「用户名」登录（账号是 lingyan），不是邮箱。",
                           color: .blue,
                           icon: "info.circle.fill")
                }
            }
        }
    }

    private func notice(_ text: String, color: Color, icon: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(text)
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 动作

    private func submit() {
        guard !isSubmitting, !username.isEmpty, !password.isEmpty else { return }
        focusedField = nil
        isSubmitting = true
        qqError = nil

        Task {
            await session.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            isSubmitting = false
            if session.isAuthenticated {
                password = ""
            }
        }
    }

    private func submitQQ() {
        guard !isQQWorking, !isSubmitting else { return }
        focusedField = nil
        qqError = nil
        isQQWorking = true

        Task {
            defer { isQQWorking = false }
            let base = ServerConfigStore.shared.config.normalizedCardAPIBase
            guard let url = URL(string: base + "/qq/authorize?mode=app") else {
                qqError = "服务器地址无效"
                return
            }
            do {
                let payload = try await qqAuth.authenticate(url: url)
                if let message = payload.errorMessage {
                    qqError = message
                    return
                }
                guard let token = payload.token, !token.isEmpty else {
                    qqError = "QQ 登录没有返回凭证"
                    return
                }
                await session.loginWithQQToken(token)
            } catch {
                qqError = error.localizedDescription
            }
        }
    }
}
