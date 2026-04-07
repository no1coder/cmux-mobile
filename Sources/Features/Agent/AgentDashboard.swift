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

    /// 连接状态指示器，显示已连接的 Mac 信息
    private var connectionIndicator: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
            let deviceName = KeychainHelper.load(key: "pairedDeviceID").flatMap {
                KeychainHelper.load(key: "deviceName_\($0)")
            } ?? String(localized: "agent.connected_device.unknown", defaultValue: "Mac")
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

            Text(String(localized: "agent.empty.description", defaultValue: "当前没有待审批的请求\nAgent 发出审批请求时会显示在这里"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(4)

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
