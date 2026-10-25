import SwiftUI

// MARK: - 尺寸类别

/// 统一的尺寸判断，避免各处散落 `horizontalSizeClass`。
///
/// iPhone 竖屏/横屏都是 `.compact`；iPad 竖屏是 `.regular`（可分栏），
/// iPad 分屏或 iPhone Plus 横屏也可能是 `.compact`。
/// 真正的「宽裕空间」判断用 **可用宽度**，而不是尺寸类别 —— 因为
/// iPhone Pro Max 横屏（932pt）其实放得下两列。
enum LayoutMode {
    /// 紧凑：单列。
    case compact
    /// 宽裕：分栏 / 多列网格。
    case regular

    /// 依据当前环境推导布局模式。
    static func current(_ sizeClass: UserInterfaceSizeClass) -> LayoutMode {
        sizeClass == .regular ? .regular : .compact
    }

    /// 依据可用宽度推导（网格列数用）。
    static func columns(forWidth width: CGFloat) -> Int {
        switch width {
        case ..<500: return 1
        case ..<900: return 2
        case ..<1300: return 3
        default: return 4
        }
    }
}

// MARK: - 平台判断

enum Platform {
    static var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
}

// MARK: - 状态颜色

/// 卡密状态的语义色。
extension CardStatus {
    /// 状态对应的 SwiftUI 颜色。
    var color: Color {
        switch self {
        case .unissued: return .secondary
        case .issued: return .accentColor
        case .used: return .green
        case .frozen: return .orange
        case .voided: return .red
        case .expired: return .red.opacity(0.75)
        }
    }
}

// MARK: - 状态标签

/// 状态徽标。
struct StatusBadge: View {
    let title: String
    let color: Color

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
            .accessibilityLabel("状态：\(title)")
    }
}

// MARK: - 统计卡片

/// 统计面板上的一格。
struct StatTile: View {
    let title: String
    let value: String
    var systemImage: String = "number"
    var tint: Color = .accentColor
    /// 副标题（口径说明）。
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if let caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - 加载态视图

/// 统一的加载 / 失败 / 空态视图。
struct StateView: View {
    enum Kind {
        case loading(String)
        case failure(APIError, retry: () -> Void)
        case empty(String)
    }

    let kind: Kind

    /// 失败态快捷构造。
    ///
    /// `Kind.failure` 有**两个**关联值（error + retry 闭包），
    /// 所以 `StateView.failure(error) { ... }` 这种尾随闭包写法是错的 ——
    /// 闭包会被当成 `StateView.init` 的尾随闭包，编译报
    /// "extra trailing closure passed in call"。
    /// 用这个工厂方法就能正常写 `StateView.failure(error) { ... }`。
    static func failure(_ error: APIError, retry: @escaping () -> Void) -> StateView {
        StateView(kind: .failure(error, retry: retry))
    }

    /// 加载态快捷构造。
    static func loading(_ message: String) -> StateView {
        StateView(kind: .loading(message))
    }

    /// 空态快捷构造。
    static func empty(_ message: String) -> StateView {
        StateView(kind: .empty(message))
    }

    var body: some View {
        switch kind {
        case .loading(let message):
            VStack(spacing: 12) {
                ProgressView()
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failure(let error, let retry):
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.orange)
                Text(error.errorDescription ?? "出错了")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("重试", action: retry)
                    .buttonStyle(.borderedProminent)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty(let message):
            VStack(spacing: 10) {
                Image(systemName: "tray")
                    .font(.largeTitle)
                    .foregroundStyle(.tertiary)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - 提示条

/// 顶部浮出的轻提示（成功/失败）。
///
/// 用于「已冻结 3 张」这类操作反馈，2.5 秒后自动消失。
struct ToastBanner: View {
    @Binding var message: String?
    var isError: Bool = false

    var body: some View {
        if let message {
            HStack(spacing: 8) {
                Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                Text(message)
                    .font(.footnote.weight(.medium))
                    .lineLimit(2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(.quaternary, lineWidth: 0.5))
            .shadow(radius: 6, y: 2)
            .padding(.horizontal)
            .transition(.move(edge: .top).combined(with: .opacity))
            .task(id: message) {
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                withAnimation { self.message = nil }
            }
        }
    }
}

// MARK: - 空态占位

/// 卡片网格里的空态。
struct EmptyGridView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.grid.2x2")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }
}
