import SwiftUI

/// 连接状态指示条：仅在非正常连接状态时显示，已连接时隐藏不占空间
struct ConnectionStatusBar: View {
    @EnvironmentObject var relayConnection: RelayConnection

    var body: some View {
        if relayConnection.status == .connected {
            // 已连接：显示延迟徽章
            if let latency = relayConnection.latencyMs {
                HStack(spacing: 4) {
                    Circle()
                        .fill(latencyColor(latency))
                        .frame(width: 5, height: 5)
                    Text("\(latency) ms")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(latencyColor(latency).opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
                .background(latencyColor(latency).opacity(0.08))
                .clipShape(Capsule())
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, 16)
                .padding(.vertical, 2)
            }
        } else {
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

    private func latencyColor(_ ms: Int) -> Color {
        if ms < 100 { return .green }
        if ms < 300 { return .yellow }
        return .red
    }
}
