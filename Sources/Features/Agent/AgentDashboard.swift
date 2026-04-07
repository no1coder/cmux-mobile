import SwiftUI

/// Agent 控制台，展示待处理审批请求和历史记录
struct AgentDashboard: View {
    @EnvironmentObject var approvalManager: ApprovalManager
    @EnvironmentObject var relayConnection: RelayConnection

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
        }
    }

    /// 未连接提示
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "agent.not_connected", defaultValue: "未连接到设备"))
                .font(.title3)
                .fontWeight(.medium)
            Text(String(localized: "agent.not_connected_desc", defaultValue: "请先在设置中扫码配对 Mac"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 主内容

    private var dashboardContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
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
            }
            .padding(16)
        }
    }

    // MARK: - 子视图

    private var emptyStateView: some View {
        Group {
            if #available(iOS 17.0, macOS 14.0, *) {
                ContentUnavailableView(
                    String(localized: "agent.empty.title", defaultValue: "无待审批请求"),
                    systemImage: "checkmark.shield",
                    description: Text(
                        String(localized: "agent.empty.description", defaultValue: "Agent 发出审批请求时会显示在这里")
                    )
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.shield")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "agent.empty.title", defaultValue: "无待审批请求"))
                        .font(.title2)
                    Text(String(localized: "agent.empty.description", defaultValue: "Agent 发出审批请求时会显示在这里"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
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
        let payload = approvalManager.buildApprovePayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .approved)
    }

    private func handleReject(_ request: ApprovalRequest) {
        let payload = approvalManager.buildRejectPayload(requestID: request.requestID)
        relayConnection.send(payload)
        approvalManager.markResolved(requestID: request.requestID, resolution: .rejected)
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
