import SwiftUI

// MARK: - 登录页

/// 登录页。
///
/// 交互流程：
/// 1. 账号（默认预填文档里的 `lingyan`）+ 密码。
/// 2. 点「登录」→ 调 `POST /login` → 拿 token 存本地 → 拉 `GET /getInfo` 拿权限。
/// 3. 成功后由根视图切到主界面；token 有效期内下次启动自动登录。
struct LoginView: View {

    @EnvironmentObject private var session: SessionStore

    @State private var username: String = AppConfig.defaultUsername
    @State private var password: String = ""
    @State private var isSubmitting = false
    @FocusState private var focusedField: Field?

    private enum Field { case username, password }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 28) {
                    header

                    formCard

                    if let error = session.loginError {
                        errorView(error)
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .animation(.easeInOut(duration: 0.2), value: session.loginError)
    }

    // MARK: 子视图

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.accentColor.opacity(0.16), Color.accentColor.opacity(0.04), .clear],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

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

    private var formCard: some View {
        VStack(spacing: 16) {
            field(
                title: "账号",
                systemImage: "person",
                text: $username,
                field: .username
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            SecureField("密码", text: $password)
                .textFieldStyle(.plain)
                .focused($focusedField, equals: .password)
                .submitLabel(.go)
                .onSubmit { submit() }
                .padding(12)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .leading) {
                    Image(systemName: "key")
                        .foregroundStyle(.secondary)
                        .padding(.leading, 12)
                }
                .overlay(alignment: .leading) {
                    Color.clear.frame(width: 34).padding(.leading, 0)
                }
                .padding(.leading, 28)
                .accessibilityLabel("密码")

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
            .disabled(isSubmitting || username.isEmpty || password.isEmpty)
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
    }

    private func field(
        title: String,
        systemImage: String,
        text: Binding<String>,
        field: Field
    ) -> some View {
        TextField(title, text: text)
            .textFieldStyle(.plain)
            .focused($focusedField, equals: field)
            .submitLabel(.next)
            .onSubmit { focusedField = .password }
            .padding(12)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(alignment: .leading) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            }
            .overlay(alignment: .leading) {
                Color.clear.frame(width: 34)
            }
            .padding(.leading, 28)
            .accessibilityLabel(title)
    }

    private func errorView(_ error: APIError) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(error.errorDescription ?? "登录失败")
                .font(.footnote)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 动作

    private func submit() {
        guard !isSubmitting, !username.isEmpty, !password.isEmpty else { return }
        focusedField = nil
        isSubmitting = true

        Task {
            await session.login(username: username.trimmingCharacters(in: .whitespaces), password: password)
            isSubmitting = false
            if session.isAuthenticated {
                password = ""
            }
        }
    }
}
