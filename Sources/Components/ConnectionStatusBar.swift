import SwiftUI

/// 连接状态指示条：仅在非正常连接状态时显示，已连接时隐藏不占空间
struct ConnectionStatusBar: View {
    @EnvironmentObject var relayConnection: RelayConnection

    /// 有效状态：当 relay 已连接但 Mac 被判为离线时，对外表现为 macOffline
    private var effectiveStatus: ConnectionStatus {
        if relayConnection.status == .connected, !relayConnection.macOnline {
            return .macOffline
        }
        return relayConnection.status
    }

    var body: some View {
        if effectiveStatus != .connected {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(CMColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var statusColor: Color {
        switch effectiveStatus {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return hasPairedCredentials ? .red : .gray
        case .macOffline: return .orange
        }
    }

    private var statusText: String {
        switch effectiveStatus {
        case .connected: return "已连接"
        case .connecting: return "连接中..."
        case .disconnected: return hasPairedCredentials ? "未连接" : "未配对"
        case .macOffline: return "Mac 离线，请检查 Mac 端 cmux"
        }
    }

    private var hasPairedCredentials: Bool {
        #if canImport(Security)
        return KeychainHelper.load(key: "pairedDeviceID") != nil
            || !DeviceStore.getDevices().isEmpty
        #else
        return false
        #endif
    }

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .green }
        if ms < 300 { return .yellow }
        return .red
    }
}
