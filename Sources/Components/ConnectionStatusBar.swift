import SwiftUI

/// 连接状态指示条：仅在非正常连接状态时显示，已连接时隐藏不占空间
struct ConnectionStatusBar: View {
    @EnvironmentObject var relayConnection: RelayConnection

    var body: some View {
        // 已连接时完全隐藏，不占任何空间
        if relayConnection.status != .connected {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            .background(statusColor.opacity(0.12))
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }

    private var statusColor: Color {
        switch relayConnection.status {
        case .connected: return .green
        case .connecting: return .yellow
        case .disconnected: return hasPairedCredentials ? .red : .gray
        case .macOffline: return .orange
        }
    }

    private var statusText: String {
        switch relayConnection.status {
        case .connected: return "已连接"
        case .connecting: return "连接中..."
        case .disconnected: return hasPairedCredentials ? "未连接" : "未配对"
        case .macOffline: return "Mac 离线"
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
}
