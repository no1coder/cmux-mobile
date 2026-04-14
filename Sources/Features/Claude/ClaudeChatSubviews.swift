import SwiftUI

// MARK: - ClaudeChatView 组件子视图
//
// 从主视图拆出的展示性子视图：会话头部、空状态、回填横幅、Plan 模式横幅、
// 流式预览、离线队列提示等。都是纯读取 @State 的 computed view，无副作用。

extension ClaudeChatView {
    // MARK: - 会话头部

    var sessionHeader: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles").font(.system(size: 24)).foregroundStyle(.purple).padding(.top, 16)
            if !sessionInfo.model.isEmpty {
                HStack(spacing: 8) {
                    Text(sessionInfo.model)
                        .font(.system(size: 12, weight: .medium)).foregroundStyle(.purple.opacity(0.8))
                        .padding(.horizontal, 10).padding(.vertical, 3)
                        .background(Color.purple.opacity(0.12)).clipShape(Capsule())
                    if !sessionInfo.context.isEmpty {
                        Text(sessionInfo.context).font(.system(size: 11)).foregroundStyle(CMColors.textTertiary)
                    }
                }
            }
            if !sessionInfo.project.isEmpty {
                Text(sessionInfo.project).font(.system(size: 11, design: .monospaced)).foregroundStyle(CMColors.textTertiary)
            }
            // Token 用量
            if showTokenUsage && !tokenUsage.isEmpty {
                TokenUsageView(
                    inputTokens: tokenUsage["input"] ?? 0,
                    outputTokens: tokenUsage["output"] ?? 0,
                    cacheTokens: tokenUsage["cache"] ?? 0,
                    compact: true
                )
                .padding(.horizontal, 20)
                .padding(.top, 4)
            }
        }
    }

    var emptyChatState: some View {
        VStack(spacing: 10) {
            switch historyLoadState {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "chat.loading_history", defaultValue: "正在加载历史消息…"))
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textTertiary)
            case .failed(let message):
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 18))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button(String(localized: "common.retry", defaultValue: "重试")) {
                    requestHistoryFetch()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            case .idle, .loaded:
                Text(String(localized: "chat.empty_prompt", defaultValue: "向 Claude 发送消息开始对话"))
                    .font(.system(size: 13))
                    .foregroundStyle(CMColors.textTertiary)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    var historyBackfillBanner: some View {
        switch fullHistoryState {
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text(String(localized: "chat.loading_more_history", defaultValue: "正在补全更早历史…"))
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(CMColors.textSecondary)
                    .multilineTextAlignment(.center)
                Button(String(localized: "chat.retry_full_history", defaultValue: "重试加载完整历史")) {
                    requestHistoryFetch(mode: .fullRefreshLegacy)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        case .idle, .loaded:
            EmptyView()
        }
    }

    /// Plan 模式横幅
    var planModeBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard")
                .font(.system(size: 13))
            Text(String(localized: "claude.plan_mode", defaultValue: "Plan 模式 — Claude 正在规划而非执行"))
                .font(.system(size: 13, weight: .medium))
            Spacer()
            Button {
                sendDirect("/plan\n")
            } label: {
                Text(String(localized: "claude.exit_plan", defaultValue: "退出 Plan"))
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color(UIColor.systemFill))
                    .clipShape(Capsule())
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.purple.opacity(0.7))
    }

    /// 流式预览视图：显示 Claude 正在生成的内容（从终端屏幕读取）
    var streamingPreviewView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !streamingPreview.isEmpty {
                // 显示实时内容
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
                        Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
                    }
                    Text(streamingPreview)
                        .font(.system(size: 14))
                        .foregroundStyle(CMColors.textPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 底部状态指示
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.5).tint(.purple.opacity(0.6))
                    Text(statusLabel)
                        .font(.system(size: 11)).foregroundStyle(CMColors.textTertiary).italic()
                }.padding(.leading, 34)
            } else {
                // 还没读到内容，显示加载状态
                HStack(alignment: .top, spacing: 8) {
                    ZStack {
                        Circle().fill(Color.purple.opacity(0.15)).frame(width: 26, height: 26)
                        Image(systemName: "sparkles").font(.system(size: 11)).foregroundStyle(.purple)
                    }
                    HStack(spacing: 6) {
                        ProgressView().scaleEffect(0.6).tint(.purple.opacity(0.6))
                        Text(statusLabel)
                            .font(.system(size: 12)).foregroundStyle(CMColors.textTertiary).italic()
                    }.padding(.top, 3)
                    Spacer()
                }
            }
        }
    }

    /// 当前状态显示文本
    var statusLabel: String {
        switch activityLabel {
        case "tool_running": return String(localized: "claude.status.tool_running", defaultValue: "执行工具中…")
        case "thinking": return String(localized: "claude.status.thinking", defaultValue: "思考中…")
        default: return String(localized: "claude.status.processing", defaultValue: "处理中…")
        }
    }

    // MARK: - 离线队列提示

    @ViewBuilder
    var offlineQueueBanner: some View {
        let count = relayConnection.offlineQueue.pendingCount
        if count > 0 {
            HStack(spacing: 6) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11))
                Text("\(count) 条消息待发送")
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(.orange)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(Color.orange.opacity(0.08))
        }
    }
}
