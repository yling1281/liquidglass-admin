import SwiftUI

// MARK: - 生成卡密表单

/// 批量生成卡密。
///
/// 对应接口：`POST /card/key/generate`
/// body: `{batchName, productId, count, durationDays}`
/// 响应 `data`: `{batchNo, successCount, taskId}`
///
/// **表单校验**：
/// - 批次名：非空（默认「默认批次」）。
/// - 数量：1 ~ 1000 之间的整数。
/// - 天数：1 ~ 36500（100 年）之间的整数。
///
/// **提交状态**：`isSubmitting` 期间禁用表单与按钮，避免重复提交。
/// **结果反馈**：成功后展示批次号与生成条数，并可一键复制批次号。
struct CardGenerateView: View {

    @ObservedObject var store: CardListStore

    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var hSizeClass

    @State private var batchName: String = "默认批次"
    @State private var productId: String = "LG-APP"
    @State private var count: Int = 50
    @State private var durationDays: Int = 30

    @State private var isSubmitting = false
    @State private var result: CardGenerateResult?
    @State private var errorMessage: String?

    /// 数量输入框的原始文本（用 String 存才能让用户中途删空不崩）。
    @State private var countText: String = "50"
    @State private var daysText: String = "30"

    @FocusState private var focusedField: Field?

    private enum Field { case batchName, count, days }

    // MARK: 校验

    private var countValue: Int? { Int(countText) }
    private var daysValue: Int? { Int(daysText) }

    private var batchNameError: String? {
        let trimmed = batchName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "批次名不能为空" }
        if trimmed.count > 64 { return "批次名过长（最多 64 字）" }
        return nil
    }

    private var countError: String? {
        guard let value = countValue else { return "请输入数字" }
        if value < 1 { return "至少生成 1 张" }
        if value > 1000 { return "单次最多生成 1000 张" }
        return nil
    }

    private var daysError: String? {
        guard let value = daysValue else { return "请输入数字" }
        if value < 1 { return "有效天数至少 1 天" }
        if value > 36500 { return "最长 36500 天（100 年）" }
        return nil
    }

    private var isValid: Bool {
        batchNameError == nil && countError == nil && daysError == nil
    }

    var body: some View {
        Form {
            batchSection
            countSection
            daysSection
            previewSection
            if let result {
                resultSection(result)
            }
            if let errorMessage {
                errorSection(errorMessage)
            }
        }
        .navigationTitle("批量生成卡密")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("取消") { dismiss() }
                    .disabled(isSubmitting)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    submit()
                } label: {
                    if isSubmitting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("生成").fontWeight(.semibold)
                    }
                }
                .disabled(!isValid || isSubmitting)
            }
        }
        .interactiveDismissDisabled(isSubmitting)
    }

    // MARK: 分区

    private var batchSection: some View {
        Section {
            TextField("批次名", text: $batchName)
                .focused($focusedField, equals: .batchName)
                .submitLabel(.next)
                .onSubmit { focusedField = .count }

            TextField("产品代码", text: $productId)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("批次信息")
        } footer: {
            if let error = batchNameError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("批次号形如 B2026102550E4A，生成后自动返回。")
            }
        }
    }

    private var countSection: some View {
        Section {
            HStack {
                Text("数量")
                Spacer()
                TextField("数量", text: $countText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .count)
                    .frame(width: 90)
                    .font(.body.monospacedDigit())
            }
        } header: {
            Text("生成数量")
        } footer: {
            if let error = countError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("单次 1 ~ 1000 张。")
            }
        }
    }

    private var daysSection: some View {
        Section {
            HStack {
                Text("有效天数")
                Spacer()
                TextField("天数", text: $daysText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .days)
                    .frame(width: 90)
                    .font(.body.monospacedDigit())
            }

            // 快捷档位
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(CardGenerateRequest.presets, id: \.label) { preset in
                        Button {
                            daysText = String(preset.days)
                            durationDays = preset.days
                        } label: {
                            Text(preset.label)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(
                                    daysValue == preset.days
                                        ? Color.accentColor.opacity(0.18)
                                        : Color.secondary.opacity(0.12),
                                    in: Capsule()
                                )
                                .foregroundStyle(daysValue == preset.days ? Color.accentColor : Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("有效期")
        } footer: {
            if let error = daysError {
                Text(error).foregroundStyle(.red)
            } else {
                Text("天数从生成时开始计算。选「永久」会写入 36500 天（100 年）。")
            }
        }
    }

    private var previewSection: some View {
        Section("生成预览") {
            LabeledContent("批次名", value: batchName.trimmingCharacters(in: .whitespacesAndNewlines))
            LabeledContent("产品代码", value: productId)
            LabeledContent("数量", value: "\(countValue ?? 0) 张")
            LabeledContent("有效期", value: "\(daysValue ?? 0) 天")
        }
        .font(.subheadline)
    }

    private func resultSection(_ result: CardGenerateResult) -> some View {
        Section {
            HStack {
                Label("生成成功", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.medium)
                Spacer()
                Text("\(result.successCount ?? 0) 张")
                    .font(.body.monospacedDigit().weight(.semibold))
            }

            if let batchNo = result.batchNo {
                HStack {
                    Text("批次号")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(batchNo)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                    Button {
                        UIPasteboard.general.string = batchNo
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("复制批次号")
                }
            }
        } footer: {
            Text("列表已自动刷新，可返回查看新生成的卡密。")
        }
    }

    private func errorSection(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.footnote)
        }
    }

    // MARK: 提交

    private func submit() {
        guard isValid, !isSubmitting else { return }
        focusedField = nil
        isSubmitting = true
        errorMessage = nil
        result = nil

        let request = CardGenerateRequest(
            batchName: batchName.trimmingCharacters(in: .whitespacesAndNewlines),
            productId: productId.trimmingCharacters(in: .whitespacesAndNewlines),
            count: countValue ?? 0,
            durationDays: daysValue ?? 0
        )

        Task {
            do {
                let data = try await APIClient.shared.sendRaw(
                    APIRequest(endpoint: APIEndpoint.cardGenerate, body: request.body)
                )
                let envelope = try JSONDecoder().decode(APIEnvelope<CardGenerateResult>.self, from: data)
                guard envelope.isSuccess else {
                    errorMessage = "生成失败：\(envelope.msg)"
                    isSubmitting = false
                    return
                }
                guard let payload = envelope.data else {
                    errorMessage = "生成失败：响应缺少数据"
                    isSubmitting = false
                    return
                }
                result = payload
                isSubmitting = false
                // 刷新列表，让新卡立刻可见
                await store.reload()
            } catch let error as APIError {
                errorMessage = error.errorDescription
                isSubmitting = false
            } catch {
                errorMessage = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}
