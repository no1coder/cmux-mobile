import Testing
import Foundation
@testable import cmux_models

@Suite("ContentBlock & ComposedMessage Tests")
struct ContentBlockTests {

    // MARK: - ContentBlock 类型判断

    @Test("text block 的 isText 为 true")
    func textBlockIsText() {
        let block = ContentBlock.text(id: UUID(), content: "hello")
        #expect(block.isText == true)
        #expect(block.isImage == false)
    }

    @Test("text block 的 textContent 返回内容")
    func textBlockContent() {
        let block = ContentBlock.text(id: UUID(), content: "hello world")
        #expect(block.textContent == "hello world")
    }

    @Test("text block 的 id 可提取")
    func textBlockId() {
        let uuid = UUID()
        let block = ContentBlock.text(id: uuid, content: "test")
        #expect(block.id == uuid)
    }

    // MARK: - ContentBlock 相等性

    @Test("相同 id 的 block 相等（不论内容）")
    func equalityById() {
        let uuid = UUID()
        let block1 = ContentBlock.text(id: uuid, content: "aaa")
        let block2 = ContentBlock.text(id: uuid, content: "bbb")
        #expect(block1 == block2)
    }

    @Test("不同 id 的 block 不相等")
    func inequalityByDifferentId() {
        let block1 = ContentBlock.text(id: UUID(), content: "same")
        let block2 = ContentBlock.text(id: UUID(), content: "same")
        #expect(block1 != block2)
    }

    // MARK: - ComposedMessage 测试

    @Test("effectiveBlocks 过滤空文本")
    func effectiveBlocksFiltersEmpty() {
        let blocks: [ContentBlock] = [
            .text(id: UUID(), content: "hello"),
            .text(id: UUID(), content: "   "),   // 纯空白
            .text(id: UUID(), content: ""),        // 空字符串
            .text(id: UUID(), content: "world"),
        ]
        let message = ComposedMessage(blocks: blocks, targetSurfaceID: "surf-1")
        #expect(message.effectiveBlocks.count == 2)
    }

    @Test("isEmpty 检测空消息")
    func isEmptyDetectsEmpty() {
        let emptyMsg = ComposedMessage(
            blocks: [.text(id: UUID(), content: "  ")],
            targetSurfaceID: "surf-1"
        )
        #expect(emptyMsg.isEmpty == true)

        let nonEmptyMsg = ComposedMessage(
            blocks: [.text(id: UUID(), content: "hello")],
            targetSurfaceID: "surf-1"
        )
        #expect(nonEmptyMsg.isEmpty == false)
    }

    @Test("imageCount 正确计数")
    func imageCountAccurate() {
        // 仅使用 text blocks 测试（UIImage 在测试中不可用时）
        let blocks: [ContentBlock] = [
            .text(id: UUID(), content: "hello"),
            .text(id: UUID(), content: "world"),
        ]
        let message = ComposedMessage(blocks: blocks, targetSurfaceID: "surf-1")
        #expect(message.imageCount == 0)
    }
}
