import Foundation

/// WebSocket 连接状态枚举
enum ConnectionStatus: String {
    case connected
    case connecting
    case disconnected
    case macOffline
}
