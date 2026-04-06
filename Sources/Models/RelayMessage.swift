import Foundation

/// Relay 协议的消息信封
struct RelayEnvelope: Codable {
    let seq: UInt64
    let ts: Int64
    let from: String
    let type: String
    let payload: [String: AnyCodable]
}
