import SwiftUI
import UIKit

/// 内嵌在聊天中的审批请求卡片 — 紧凑版，直接在对话流中操作
struct InlineApprovalView: View {
    let request: ApprovalRequest
    let onApprove: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 左侧警示图标
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: "exclamationmark.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 8) {
                // 头部：需要审批 + 倒计时
                HStack {
                    Text(String(localized: "inline_approval.title", defaultValue: "需要审批"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.orange)

                    Spacer()

                    // 倒计时（使用系统 timer 样式，避免 TimelineView 每秒刷新整个视图）
                    let deadline = request.timestamp.addingTimeInterval(Double(request.timeoutSeconds))
                    if deadline > Date() {
                        Text(deadline, style: .timer)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(deadline.timeIntervalSinceNow > 10 ? CMColors.textTertiary : .red)
                    } else {
                        Text(String(localized: "inline_approval.expired", defaultValue: "已超时"))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                // 工具/操作名称
                Text(request.action)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(CMColors.textPrimary)
                    .lineLimit(3)

                // 上下文
                if !request.context.isEmpty {
                    Text(request.context)
                        .font(.system(size: 11))
                        .foregroundStyle(CMColors.textTertiary)
                        .lineLimit(2)
                }

                // 按钮
                HStack(spacing: 10) {
                    Button {
                        Haptics.warning()
                        onReject()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(localized: "inline_approval.reject", defaultValue: "拒绝"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.red)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.red.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Button {
                        Haptics.success()
                        onApprove()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                            Text(String(localized: "inline_approval.approve", defaultValue: "批准"))
                                .font(.system(size: 12, weight: .medium))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(Color.green)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }
}
