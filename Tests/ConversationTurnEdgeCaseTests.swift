import XCTest
@testable import cmux_models

final class ConversationTurnEdgeCaseTests: XCTestCase {

    func testSystemMessagesGroupedWithReplies() {
        // system 消息夹在 user 和 assistant 之间，应归入同一轮次的 replies
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q", timestamp: Date()),
            ClaudeChatItem(id: "s1", role: .system, content: "sys", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "A", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].replies.count, 2)  // system + assistant
    }

    func testLargeConversation() {
        // 100 轮对话：验证性能与正确性
        var items: [ClaudeChatItem] = []
        for i in 0..<100 {
            items.append(ClaudeChatItem(id: "u\(i)", role: .user, content: "Q\(i)", timestamp: Date()))
            items.append(ClaudeChatItem(id: "a\(i)", role: .assistant, content: "A\(i)", timestamp: Date()))
        }
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 100)
        XCTAssertEqual(turns[50].question?.content, "Q50")
        XCTAssertEqual(turns[50].replies.count, 1)
    }

    func testMixedToolBurst() {
        // 多个连续 tool 调用应都归入同一轮次
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "fix", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Read"), content: "f1", timestamp: Date()),
            ClaudeChatItem(id: "t2", role: .tool(name: "Edit"), content: "f1", timestamp: Date()),
            ClaudeChatItem(id: "t3", role: .tool(name: "Bash"), content: "test", timestamp: Date()),
            ClaudeChatItem(id: "t4", role: .tool(name: "Read"), content: "f2", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "done", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].replies.count, 5)
    }

    func testFirstIndexTrackedCorrectly() {
        // 验证 firstIndex 记录了每个轮次在原始列表中的起始位置
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q1", timestamp: Date()),  // index 0
            ClaudeChatItem(id: "a1", role: .assistant, content: "A1", timestamp: Date()),
            ClaudeChatItem(id: "u2", role: .user, content: "Q2", timestamp: Date()),  // index 2
            ClaudeChatItem(id: "a2", role: .assistant, content: "A2", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].firstIndex, 0)
        XCTAssertEqual(turns[1].firstIndex, 2)
    }

    func testToolOnlyTurnAfterUser() {
        // user 之后只有 tool 消息（无 assistant 结束）也应正常分组
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "go", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Bash"), content: "output", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].question?.id, "u1")
        XCTAssertEqual(turns[0].replies.count, 1)
    }
}
