import SwiftUI

// MARK: - 对接情况

/// 对接情况页。
///
/// 展示**各对接渠道 / 接口的当前状态与结果**：
///
/// 1. **渠道**：卡密后台 `GET /card/channel/list` 的发卡渠道配置，
///    标注是否启用及服务端备注（实测两个渠道均为「占位配置，本期不发起外部请求」）。
/// 2. **接口**：逐个实调 18 个对接接口，实时反映连通性与返回结果。
///    写接口用**探测性调用**（不存在的 id / count=0），不改动真实数据。
/// 3. **服务端**：三套服务的地址与登录态。
///
/// 检测结果是**真实请求的产物**，不是写死的文案。
struct IntegrationView: View {

    @ObservedObject var store: IntegrationStore
    @ObservedObject var shopStore: ShopStore

    @Environment(\.horizontalSizeClass) private var hSizeClass

    private var isRegular: Bool { hSizeClass == .regular }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                serverSection
                channelSection
                endpointSection
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("对接情况")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await store.runChecks() }
                } label: {
                    if store.isChecking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(store.isChecking)
                .accessibilityLabel("重新检测")
            }
        }
        .refreshable {
            await store.loadChannels()
            await store.runChecks()
        }
        .task {
            await store.loadChannels()
            if store.checks.isEmpty {
                await store.runChecks()
            }
        }
        .overlay(alignment: .top) {
            ToastBanner(message: $store.toast, isError: false)
        }
    }

    // MARK: 服务端

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("对接服务")
                .font(.headline)

            VStack(spacing: 0) {
                serverRow(
                    name: "卡密后台",
                    url: "z7k2m9xq.lingyan.cyou/prod-api",
                    state: .ok("已登录"),
                    detail: "鉴权：Bearer token"
                )
                Divider()
                serverRow(
                    name: "商城前台",
                    url: "www.siyecaogf.cn",
                    state: .ok("公开接口"),
                    detail: "无鉴权 · POST 用 form 编码"
                )
                Divider()
                serverRow(
                    name: "店铺后台",
                    url: "lgk3f9x2p.lingyan.cyou",
                    state: shopStore.shopAdminToken == nil ? .warn("未登录") : .ok("已登录"),
                    detail: shopStore.loginError ?? "管理端接口需单独账号"
                )
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private enum ServerState {
        case ok(String)
        case warn(String)
    }

    private func serverRow(name: String, url: String, state: ServerState, detail: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.medium))
                Text(url)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            switch state {
            case .ok(let text):
                StatusBadge(title: text, color: .green)
            case .warn(let text):
                StatusBadge(title: text, color: .orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 渠道

    private var channelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("发卡渠道")
                    .font(.headline)
                Spacer()
                if let lastChecked = store.lastCheckedAt {
                    Text("检测于 \(lastChecked.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            switch store.channelState {
            case .loading where store.channels.isEmpty:
                StateView.loading("正在加载渠道…")
                    .frame(height: 140)
            case .failed(let error) where store.channels.isEmpty:
                StateView.failure(error) {
                    Task { await store.loadChannels() }
                }
                .frame(height: 180)
            case .loaded(let list) where list.isEmpty:
                StateView.empty("没有配置任何发卡渠道")
                    .frame(height: 140)
            default:
                VStack(spacing: 0) {
                    ForEach(Array(store.channels.enumerated()), id: \.element.id) { index, channel in
                        channelRow(channel)
                        if index < store.channels.count - 1 { Divider() }
                    }
                }
                .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private func channelRow(_ channel: CardChannel) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.channelName)
                    .font(.subheadline.weight(.medium))
                Text(channel.channelCode)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                if let remark = channel.remark, !remark.isEmpty {
                    Text(remark)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            StatusBadge(
                title: channel.enabled ? "已启用" : "未启用",
                color: channel.enabled ? .green : .secondary
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    // MARK: 接口检测

    private var endpointSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("接口连通性")
                    .font(.headline)
                Spacer()
                if !store.checks.isEmpty {
                    let ok = store.checks.filter(\.isSuccess).count
                    Text("\(ok)/\(store.checks.count) 正常")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if store.checks.isEmpty {
                if store.isChecking {
                    StateView.loading("正在逐个检测接口…")
                        .frame(height: 200)
                } else {
                    StateView.empty("尚未检测")
                        .frame(height: 160)
                }
            } else {
                // 按服务分组展示
                ForEach(serviceGroups, id: \.0) { service, items in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(service)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 4)

                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, check in
                                endpointRow(check)
                                if index < items.count - 1 { Divider() }
                            }
                        }
                        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    /// 按服务分组，保持声明顺序。
    private var serviceGroups: [(String, [EndpointCheck])] {
        var order: [String] = []
        var map: [String: [EndpointCheck]] = [:]
        for check in store.checks {
            if map[check.service] == nil {
                order.append(check.service)
                map[check.service] = []
            }
            map[check.service]?.append(check)
        }
        return order.map { ($0, map[$0] ?? []) }
    }

    private func endpointRow(_ check: EndpointCheck) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(check.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.primary)
                Text(check.purpose)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if case .success(let outcome) = check.result {
                    Text(outcome.summary)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                StatusBadge(title: check.statusTitle, color: check.statusColor)
                if check.requiresAuth {
                    Text("需鉴权")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
