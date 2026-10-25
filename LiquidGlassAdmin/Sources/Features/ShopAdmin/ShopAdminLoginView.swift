import SwiftUI

// MARK: - 店铺后台登录门

/// 未登录店铺后台时显示的登录界面。
///
/// 之所以单独做一个「门」而不是直接跳到设置页：
/// 用户点「店铺」tab 就是想看店铺数据，把他甩到设置页再让他找，
/// 体验断裂。这里就地登录完立刻进模块列表。
struct ShopAdminLoginView: View {

    @ObservedObject var shopAdmin: ShopAdminSession
    @ObservedObject var session: SessionStore

    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isSubmitting = false
    @State private var hint: String?

    @FocusState private var focused: Field?
    private enum Field { case username, password }

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 22) {
                    header
                    card
                    if let message = shopAdmin.error ?? hint {
                        notice(message)
                    }
                }
                .frame(maxWidth: 460)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
                .frame(minHeight: geo.size.height)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("店铺管理")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: prefill)
    }

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "storefront.fill")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
            Text("店铺管理")
                .font(.title2.weight(.bold))
            Text("商品、订单与会员")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var card: some View {
        VStack(spacing: 14) {
            inputRow(icon: "envelope", placeholder: "登录邮箱", field: .username, isSecure: false)
            inputRow(icon: "key", placeholder: "密码", field: .password, isSecure: true)

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView().controlSize(.small).tint(.white)
                    }
                    Text(isSubmitting ? "登录中…" : "登录店铺后台")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSubmitting || username.isEmpty || password.isEmpty)

            // 卡密后台和店铺后台用同一套凭证，这里一键带入
            if let account = session.user?.userName, !account.isEmpty {
                Button {
                    username = account
                    hint = "已填入卡密后台账号。两边密码相同，输入密码即可。"
                } label: {
                    Label("用卡密后台账号（\(account)）", systemImage: "arrow.down.circle")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
            }
        }
        .padding(20)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.07), radius: 18, y: 6)
    }

    private func inputRow(
        icon: String,
        placeholder: String,
        field: Field,
        isSecure: Bool
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 20)

            Group {
                if isSecure {
                    SecureField(placeholder, text: $password)
                        .textContentType(.password)
                } else {
                    TextField(placeholder, text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                }
            }
            .textFieldStyle(.plain)
            .focused($focused, equals: field)
            .submitLabel(field == .username ? .next : .go)
            .onSubmit {
                if field == .username {
                    focused = .password
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

    private func notice(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: 动作

    private func prefill() {
        guard username.isEmpty else { return }
        // 卡密后台若已登录，直接用它的账号名（现在的邮箱别名让两边账号一致）
        if let name = session.user?.userName, name.contains("@") {
            username = name
        }
    }

    private func submit() {
        guard !isSubmitting else { return }
        focused = nil
        isSubmitting = true
        hint = nil

        Task {
            await shopAdmin.login(
                username: username.trimmingCharacters(in: .whitespaces),
                password: password
            )
            isSubmitting = false
            if shopAdmin.isLoggedIn {
                password = ""
            }
        }
    }
}
