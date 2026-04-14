import SwiftUI

/// Agent 控制台，展示待处理审批请求和历史记录
struct AgentDashboard: View {
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var activityStore: ActivityStore

    /// 自动批准只读工具
    @AppStorage("approvalAutoReadOnly") private var autoReadOnly = true
    /// 本次会话全部自动批准
    @AppStorage("approvalApproveAll") private var approveAll = false

    /// 最近一次审批操作的反馈（1.2s 自动消失）
    @State private var actionFeedback: String?
    @State private var feedbackTask: Task<Void, Never>?

    var body: some View {
        NavigationStack {
            Group {
                if relayConnection.status != .connected {
                    notConnectedView
                } else if approvalManager.pendingRequests.isEmpty && approvalManager.resolvedRequests.isEmpty {
                    emptyStateView
                } else {
                    dashboardContent
                }
            }
            .navigationTitle(String(localized: "agent.dashboard.title", defaultValue: "Agent"))
            .navigationBarTitleDisplayMode(.inline)
            .overlay(alignment: .top) {
                if let text = actionFeedback {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Text(text)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .padding(.top, 8)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
        .onDisappear { feedbackTask?.cancel() }
    }

    private func showFeedback(_ text: String) {
        feedbackTask?.cancel()
        withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = text }
        feedbackTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeInOut(duration: 0.2)) { actionFeedback = nil }
        }
    }

    /// 未连接提示
    private var notConnectedView: some View {
        PairMacOnboardingView(
            title: String(localized: "agent.not_connected", defaultValue: "未连接到设备"),
            message: String(localized: "agent.not_connected_desc", defaultValue: "重新配对或切换 Mac 后，即可继续处理审批请求与 Agent 活动。")
        )
        .environmentObject(relayConnection)
    }

    /// 连接状态指示器，显示已连接的 Mac 信息
    private var connectionIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            let deviceName = DeviceStore.getActiveDevice()?.name
                ?? DeviceStore.getDevices().first?.name
                ?? String(localized: "agent.connected_device.unknown", defaultValue: "Mac")
            Text(String(localized: "agent.connected_to", defaultValue: "已连接：\(deviceName)"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 主内容

    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                // 连接状态指示器
                connectionIndicator

                // 审批策略设置
                approvalPolicySection

                // 待处理区块
                if !approvalManager.pendingRequests.isEmpty {
                    sectionHeader(
                        title: String(localized: "agent.pending.title", defaultValue: "待审批"),
                        count: approvalManager.pendingRequests.count
                    )
                    ForEach(approvalManager.pendingRequests) { request in
                        ApprovalRequestView(
                            request: request,
                            onApprove: { handleApprove(request) },
                            onReject: { handleReject(request) }
                        )
                        .swipeActions(edge: .trailing) {
                            Button {
                                handleApprove(request)
                            } label: {
                                Label(
                                    String(localized: "approval.action.approve", defaultValue: "批准"),
                                    systemImage: "checkmark.circle"
                                )
                            }
                            .tint(.green)
                        }
                        .swipeActions(edge: .leading) {
                            Button(role: .destructive) {
                                handleReject(request)
                            } label: {
                                Label(
                                    String(localized: "approval.action.reject", defaultValue: "拒绝"),
                                    systemImage: "xmark.circle"
                                )
                            }
                        }
                    }
                }

                // 已解决历史区块
                if !approvalManager.resolvedRequests.isEmpty {
                    sectionHeader(
                        title: String(localized: "agent.resolved.title", defaultValue: "历史记录"),
                        count: approvalManager.resolvedRequests.count
                    )
                    ForEach(approvalManager.resolvedRequests.reversed()) { resolved in
                        resolvedRow(resolved)
                    }
                }

                // 活动日志区块
                if !activityStore.items.isEmpty {
                    activitySection
                }
            }
            .padding(16)
        }
        .onChange(of: approvalManager.pendingRequests) { _, pending in
            // 根据策略自动批准
            autoApprovePendingRequests(pending)
        }
    }

    // MARK: - 审批策略

    private var approvalPolicySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "gearshape")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(localized: "agent.policy.title", defaultValue: "审批策略"))
                    .font(.subheadline)
                    .fontWeight(.medium)
            }

            VStack(spacing: 0) {
                Toggle(isOn: $autoReadOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "agent.policy.auto_readonly", defaultValue: "自动批准只读工具"))
                            .font(.subheadline)
                        Text("Read / Glob / Grep / WebSearch")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
                .tint(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().padding(.leading, 12)

                Toggle(isOn: $approveAll) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "agent.policy.approve_all", defaultValue: "本次会话全部自动批准"))
                            .font(.subheadline)
                        Text(String(localized: "agent.policy.approve_all_desc", defaultValue: "所有工具调用自动批准，请谨慎使用"))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                .toggleStyle(.switch)
                .tint(.orange)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
            }
            .background(Color.secondary.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .onChange(of: autoReadOnly) { _, newValue in
            syncPolicyFromToggles(readOnly: newValue, all: approveAll)
        }
        .onChange(of: approveAll) { _, newValue in
            syncPolicyFromToggles(readOnly: autoReadOnly, all: newValue)
        }
    }

    /// 同步 UI toggle 到 ApprovalManager 策略
    private func syncPolicyFromToggles(readOnly: Bool, all: Bool) {
        var newPolicy = ApprovalPolicy()
        newPolicy.autoApproveTools = readOnly ? ApprovalPolicy.readOnlyTools : []
        newPolicy.approveAllForSession = all
        approvalManager.policy = newPolicy
        approvalManager.savePolicy()
    }

    /// 自动批准符合策略的待处理请求
    private func autoApprovePendingRequests(_ pending: [ApprovalRequest]) {
        for request in pending {
            if approvalManager.policy.shouldAutoApprove(toolName: request.action) {
                handleApprove(request)
                activityStore.add(
                    type: .approval,
                    title: String(localized: "activity.auto_approved", defaultValue: "自动批准"),
                    detail: request.action
                )
            }
        }
    }

    // MARK: - 活动日志

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(
                title: String(localized: "agent.activity.title", defaultValue: "活动日志"),
                count: activityStore.items.count
            )
            ForEach(activityStore.items.prefix(20)) { item in
                activityRow(item)
            }
        }
    }

    private func activityRow(_ item: ActivityStore.ActivityItem) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.type.icon)
                .foregroundStyle(activityColor(item.type))
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.caption)
                    .fontWeight(.medium)
                if !item.detail.isEmpty {
                    Text(item.detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Text(item.timestamp, style: .relative)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.secondary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func activityColor(_ type: ActivityStore.ActivityType) -> Color {
        switch type {
        case .approval: return .green
        case .taskComplete: return .blue
        case .taskFailed: return .red
        case .info: return .gray
        }
    }

    // MARK: - 子视图

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Spacer()

            // 友好的插图
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 120, height: 120)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.green.opacity(0.7))
            }

            Text(String(localized: "agent.empty.title", defaultValue: "一切就绪"))
                .font(.title2)
                .fontWeight(.semibold)

            Text(String(localized: "agent.empty.description", defaultValue: "当前没有待审批的请求"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Text(String(localized: "agent.empty.guidance", defaultValue: "当 Mac 上的 Claude Code 需要执行文件修改或运行命令时，审批请求将出现在这里"))
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.horizontal, 24)

            // 连接指示器
            connectionIndicator
                .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.title3)
                .fontWeight(.semibold)
            Text("(\(count))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func resolvedRow(_ resolved: ResolvedRequest) -> some View {
        HStack(spacing: 10) {
            // 状态图标
            Image(systemName: resolutionIcon(resolved.resolution))
                .foregroundStyle(resolutionColor(resolved.resolution))
                .font(.body)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(resolved.request.action)
                    .font(.system(.caption, design: .monospaced))
                    .lineLimit(1)
                Text(resolved.request.agent)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(resolutionLabel(resolved.resolution))
                .font(.caption)
                .foregroundStyle(resolutionColor(resolved.resolution))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 辅助方法

    private func handleApprove(_ request: ApprovalRequest) {
        Haptics.light()
        let payload = approvalManager.buildApprovePayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .approved)
        showFeedback(String(
            localized: "agent.feedback.approved",
            defaultValue: "已批准 \(request.action)"
        ))
    }

    private func handleReject(_ request: ApprovalRequest) {
        Haptics.rigid()
        let payload = approvalManager.buildRejectPayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .rejected)
        showFeedback(String(
            localized: "agent.feedback.rejected",
            defaultValue: "已拒绝 \(request.action)"
        ))
    }

    private func resolutionIcon(_ resolution: ApprovalResolution) -> String {
        switch resolution {
        case .approved: return "checkmark.circle.fill"
        case .rejected: return "xmark.circle.fill"
        case .expired:  return "clock.badge.xmark"
        }
    }

    private func resolutionColor(_ resolution: ApprovalResolution) -> Color {
        switch resolution {
        case .approved: return .green
        case .rejected: return .red
        case .expired:  return .orange
        }
    }

    private func resolutionLabel(_ resolution: ApprovalResolution) -> String {
        switch resolution {
        case .approved:
            return String(localized: "approval.status.approved", defaultValue: "已批准")
        case .rejected:
            return String(localized: "approval.status.rejected", defaultValue: "已拒绝")
        case .expired:
            return String(localized: "approval.status.expired", defaultValue: "已超时")
        }
    }
}
