import SwiftUI

// MARK: - 卡密详情

/// 卡密详情页。
///
/// iPhone：从列表推栈进入。
/// iPad：常驻右侧内容区（未选中时显示占位提示）。
struct CardDetailView: View {

    let card: CardKey?

    var body: some View {
        Group {
            if let card {
                detailContent(card)
            } else {
                placeholder
            }
        }
        .navigationTitle("卡密详情")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var placeholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.slash")
                .font(.system(size: 44))
                .foregroundStyle(.tertiary)
            Text("选择一张卡查看详情")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func detailContent(_ card: CardKey) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header(card)
                sections(card)
            }
            .padding()
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: 头部

    private func header(_ card: CardKey) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(card.cardNo)
                    .font(.title3.monospaced().weight(.bold))
                    .textSelection(.enabled)
                Spacer()
                StatusBadge(
                    title: card.statusTitle,
                    color: card.cardStatus?.color ?? .secondary
                )
            }

            if let remark = card.remark, !remark.isEmpty {
                Text(remark)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    // MARK: 字段分组

    private func sections(_ card: CardKey) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            group("基本信息", rows: [
                .init("卡号", card.cardNo, mono: true),
                .init("密钥掩码", card.secretMask ?? "—", mono: true),
                .init("产品代码", card.productCode ?? "—", mono: true),
                .init("批次号", card.batchNo ?? "—", mono: true),
                .init("状态", card.statusTitle),
            ])

            group("绑定信息", rows: [
                .init("绑定设备", card.deviceDisplay, mono: true),
                .init("绑定账号", card.bindAccount ?? "—", mono: true),
                .init("绑定次数", card.bindCount.map { "\($0) / \(card.maxBind ?? 1)" } ?? "—"),
                .init("渠道", card.channelCode ?? "—", mono: true),
                .init("订单号", card.orderNo ?? "—", mono: true),
            ])

            group("有效期", rows: [
                .init("创建时间", card.createDate.map(Self.format) ?? "—"),
                .init("到期时间", card.expireDate.map(Self.format) ?? "—"),
                .init("有效天数", card.durationDays.map { "\($0) 天" } ?? "—"),
                .init("剩余", remainingText(card)),
            ])

            group("记录 ID", rows: [
                .init("ID", "\(card.id)", mono: true),
            ])
        }
    }

    private func remainingText(_ card: CardKey) -> String {
        if card.isPermanent { return "永久有效" }
        guard let days = card.remainingDays else { return "—" }
        if days < 0 { return "已过期 \(-days) 天" }
        return "剩余 \(days) 天"
    }

    private func group(_ title: String, rows: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(alignment: .top) {
                        Text(row.label)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(width: 100, alignment: .leading)
                        Text(row.value)
                            .font(row.mono ? .subheadline.monospaced() : .subheadline)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)

                    if index < rows.count - 1 {
                        Divider()
                    }
                }
            }
            .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: 格式化

    private struct Row {
        let label: String
        let value: String
        var mono: Bool = false

        init(_ label: String, _ value: String, mono: Bool = false) {
            self.label = label
            self.value = value
            self.mono = mono
        }
    }

    static func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }

    /// 短日期（网页版表格「到期」列用的格式：`yyyy-MM-dd`）。
    static func formatShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
