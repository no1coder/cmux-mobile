import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 混合消息中的内容块（文字或图片交替排列）
enum ContentBlock: Identifiable, Equatable {
    case text(id: UUID, content: String)
    #if canImport(UIKit)
    case image(id: UUID, data: Data, thumbnail: UIImage)
    #else
    case image(id: UUID, data: Data, thumbnail: Data)
    #endif

    var id: UUID {
        switch self {
        case .text(let id, _): return id
        case .image(let id, _, _): return id
        }
    }

    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    var textContent: String? {
        if case .text(_, let content) = self { return content }
        return nil
    }

    static func == (lhs: ContentBlock, rhs: ContentBlock) -> Bool {
        lhs.id == rhs.id
    }
}

/// 一条待发送的混合消息（文字 + 图片交替）
struct ComposedMessage {
    let blocks: [ContentBlock]
    let targetSurfaceID: String

    /// 过滤掉空文本块，返回有效内容
    var effectiveBlocks: [ContentBlock] {
        blocks.filter { block in
            switch block {
            case .text(_, let content):
                return !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .image:
                return true
            }
        }
    }

    /// 是否有实际内容
    var isEmpty: Bool {
        effectiveBlocks.isEmpty
    }

    /// 图片数量
    var imageCount: Int {
        blocks.filter(\.isImage).count
    }
}
