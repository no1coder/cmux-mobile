import Foundation

/// 混合消息发送器：将 ComposedMessage 序列化为 Relay 事件序列
/// 协议：composed_msg.start → composed_msg.block × N → composed_msg.end
@MainActor
final class ComposedMessageSender {

    private let relayConnection: RelayConnection

    init(relayConnection: RelayConnection) {
        self.relayConnection = relayConnection
    }

    /// 发送混合消息（文字 + 图片）
    /// - Parameter message: 待发送的混合消息
    func send(_ message: ComposedMessage) {
        let effectiveBlocks = message.effectiveBlocks
        guard !effectiveBlocks.isEmpty else { return }

        let msgID = UUID().uuidString

        // 1. 发送消息开始事件
        relayConnection.send([
            "method": "composed_msg.start",
            "params": [
                "msg_id": msgID,
                "surface_id": message.targetSurfaceID,
                "block_count": effectiveBlocks.count,
                "image_count": message.imageCount,
            ],
        ])

        // 2. 逐块发送
        for (index, block) in effectiveBlocks.enumerated() {
            switch block {
            case .text(_, let content):
                relayConnection.send([
                    "method": "composed_msg.block",
                    "params": [
                        "msg_id": msgID,
                        "index": index,
                        "type": "text",
                        "content": content,
                    ],
                ])

            case .image(_, let data, _):
                relayConnection.send([
                    "method": "composed_msg.block",
                    "params": [
                        "msg_id": msgID,
                        "index": index,
                        "type": "image",
                        "format": "jpeg",
                        "size": data.count,
                        "data": data.base64EncodedString(),
                    ],
                ])
            }
        }

        // 3. 发送消息结束事件
        relayConnection.send([
            "method": "composed_msg.end",
            "params": [
                "msg_id": msgID,
            ],
        ])
    }
}
