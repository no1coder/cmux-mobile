import SwiftUI

/// 显示 WebSocket 连接状态和延迟的徽章视图
struct ConnectionStatusBadge: View {
    let status: ConnectionStatus
    let latencyMs: Int?

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            if let ms = latencyMs, status == .connected {
                Text("\(ms)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text(statusLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }

    /// 根据状态返回对应颜色
    private var statusColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return .red
        case .macOffline:
            return .orange
        }
    }

    /// 状态文字描述
    private var statusLabel: String {
        switch status {
        case .connected:
            return "已连接"
        case .connecting:
            return "连接中"
        case .disconnected:
            return "未连接"
        case .macOffline:
            return "Mac 离线"
        }
    }
}
