import SwiftUI

/// 单条审批请求卡片，含倒计时和批准/拒绝按钮
struct ApprovalRequestView: View {
    let request: ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 头部：Agent 名称 + 倒计时
            HStack {
                Label(request.agent, systemImage: "cpu")
                    .font(.headline)
                    .foregroundStyle(.primary)

                Spacer()

                // 倒计时（使用 TimelineView 每秒刷新）
                TimelineView(.periodic(from: Date(), by: 1)) { _ in
                    let remaining = max(
                        0,
                        request.timeoutSeconds - Int(Date().timeIntervalSince(request.timestamp))
                    )
                    Text(remaining > 0 ? "\(remaining)s" : String(localized: "approval.expired", defaultValue: "已超时"))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(remaining > 10 ? Color.secondary : Color.red)
                }
            }

            // 操作内容（等宽字体）
            Text(request.action)
                .font(.system(.body, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // 上下文说明
            if !request.context.isEmpty {
                Text(request.context)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 批准/拒绝按钮
            HStack(spacing: 12) {
                Button {
                    onReject()
                } label: {
                    Label(
                        String(localized: "approval.reject", defaultValue: "拒绝"),
                        systemImage: "xmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)

                Button {
                    onApprove()
                } label: {
                    Label(
                        String(localized: "approval.approve", defaultValue: "批准"),
                        systemImage: "checkmark.circle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
            }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
        )
    }
}
