import SwiftUI

/// 发布动态弹窗:文字动态(图片上传链路未接)。
/// 成功后由 AppModel 关闭并刷新首页;失败原因显示在底部。
struct ComposerView: View {
    @Bindable var model: AppModel
    @Environment(\.dismiss) private var dismiss
    private let charLimit = 2000

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider()
            ZStack(alignment: .topLeading) {
                TextEditor(text: $model.publishDraft)
                    .padding(12)
                    .font(.body)
                if model.publishDraft.isEmpty {
                    Text("说点什么…")
                        .foregroundStyle(.tertiary)
                        .padding(.top, 20)
                        .padding(.leading, 17)
                        .allowsHitTesting(false)
                }
            }
            .frame(minHeight: 180)
            HStack {
                if let status = model.publishStatus, !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Text("\(model.publishDraft.count)/\(charLimit)")
                    .font(.caption2)
                    .foregroundStyle(model.publishDraft.count > charLimit ? .red : .secondary)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .frame(width: 480, height: 300)
        .onAppear { model.clearPublishStatus() }
    }

    private var headerBar: some View {
        HStack {
            Button("取消") {
                model.clearPublishStatus()
                dismiss()
            }
            .buttonStyle(.borderless)

            Spacer()
            Text("发布动态")
                .font(.headline)
            Spacer()

            if model.isPublishingFeed {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button("发布") {
                    Task { await model.publishFeed() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.coolapkGreen)
                .disabled(!canPublish)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var canPublish: Bool {
        let trimmed = model.publishDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && model.publishDraft.count <= charLimit
    }
}
