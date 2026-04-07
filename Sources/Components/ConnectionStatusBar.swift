import SwiftUI

/// 连接状态指示条：显示当前 WebSocket 连接状态
struct ConnectionStatusBar: View {
    @EnvironmentObject var relayConnection: RelayConnection

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            if let latency = relayConnection.latencyMs, relayConnection.status == .connected {
                Text("\(latency)ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(statusBackgroundColor)
    }

    // MARK: - 状态属性

    /// 状态圆点颜色
    private var statusColor: Color {
        switch relayConnection.status {
        case .connected:
            return .green
        case .connecting:
            return .yellow
        case .disconnected:
            return hasPairedCredentials ? .red : .gray
        case .macOffline:
            return .orange
        }
    }

    /// 状态文本
    private var statusText: String {
        switch relayConnection.status {
        case .connected:
            return String(localized: "status.connected", defaultValue: "已连接")
        case .connecting:
            return String(localized: "status.connecting", defaultValue: "连接中...")
        case .disconnected:
            if hasPairedCredentials {
                return String(localized: "status.disconnected", defaultValue: "未连接")
            } else {
                return String(localized: "status.not_paired", defaultValue: "未配对")
            }
        case .macOffline:
            return String(localized: "status.mac_offline", defaultValue: "Mac 离线")
        }
    }

    /// 状态栏背景色
    private var statusBackgroundColor: Color {
        switch relayConnection.status {
        case .connected:
            return Color.green.opacity(0.1)
        case .connecting:
            return Color.yellow.opacity(0.1)
        case .disconnected:
            return hasPairedCredentials ? Color.red.opacity(0.1) : Color.gray.opacity(0.1)
        case .macOffline:
            return Color.orange.opacity(0.1)
        }
    }

    /// 检查 Keychain 中是否有配对凭据
    private var hasPairedCredentials: Bool {
        #if canImport(Security)
        return KeychainHelper.load(key: "pairedDeviceID") != nil
        #else
        return false
        #endif
    }
}
