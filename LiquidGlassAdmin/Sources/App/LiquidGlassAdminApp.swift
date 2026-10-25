import SwiftUI

// MARK: - App 入口

/// App 根视图：负责在「登录」与「主界面」之间切换。
struct AppRootView: View {

    @EnvironmentObject private var session: SessionStore
    @State private var isCheckingSession = true

    var body: some View {
        Group {
            if isCheckingSession {
                launchScreen
            } else if session.isAuthenticated {
                RootView()
            } else {
                LoginView()
            }
        }
        .task {
            // 启动时尝试用已保存的 token 自动登录。
            await session.attemptAutoLogin()
            isCheckingSession = false
        }
    }

    private var launchScreen: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 46))
                .foregroundStyle(.tint)
            ProgressView()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

// MARK: - App 定义

@main
struct LiquidGlassAdminApp: App {

    @StateObject private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environmentObject(session)
        }
    }
}
