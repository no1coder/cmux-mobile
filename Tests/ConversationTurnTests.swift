import XCTest
@testable import cmux_models

final class ConversationTurnTests: XCTestCase {

    func testEmptyMessages() {
        let turns = ConversationTurn.group([])
        XCTAssertTrue(turns.isEmpty)
    }

    func testSingleUserMessage() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "hello", timestamp: Date())
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].question?.id, "u1")
        XCTAssertTrue(turns[0].replies.isEmpty)
    }

    func testMultiTurnConversation() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q1", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "A1", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Bash"), content: "ls", timestamp: Date()),
            ClaudeChatItem(id: "u2", role: .user, content: "Q2", timestamp: Date()),
            ClaudeChatItem(id: "a2", role: .assistant, content: "A2", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].question?.content, "Q1")
        XCTAssertEqual(turns[0].replies.count, 2)
        XCTAssertEqual(turns[0].replyCount, 2)
        XCTAssertEqual(turns[1].question?.content, "Q2")
        XCTAssertEqual(turns[1].replies.count, 1)
    }

    func testSessionStartReplies() {
        let items = [
            ClaudeChatItem(id: "a0", role: .assistant, content: "Welcome", timestamp: Date()),
            ClaudeChatItem(id: "u1", role: .user, content: "Hi", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "Hello", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        XCTAssertNil(turns[0].question)
        XCTAssertTrue(turns[0].isSessionStart)
        XCTAssertEqual(turns[0].replies.count, 1)
        XCTAssertEqual(turns[1].question?.content, "Hi")
        XCTAssertEqual(turns[1].replies.count, 1)
    }

    func testOnlyAssistantMessages() {
        let items = [
            ClaudeChatItem(id: "a1", role: .assistant, content: "A1", timestamp: Date()),
            ClaudeChatItem(id: "a2", role: .assistant, content: "A2", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertTrue(turns[0].isSessionStart)
        XCTAssertEqual(turns[0].replies.count, 2)
    }

    func testThinkingAndToolsGroupedCorrectly() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "fix bug", timestamp: Date()),
            ClaudeChatItem(id: "th1", role: .thinking, content: "let me think", timestamp: Date()),
            ClaudeChatItem(id: "t1", role: .tool(name: "Read"), content: "file.swift", timestamp: Date()),
            ClaudeChatItem(id: "t2", role: .tool(name: "Edit"), content: "file.swift", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "Fixed", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 1)
        XCTAssertEqual(turns[0].replies.count, 4)
    }

    func testConsecutiveUserMessages() {
        let items = [
            ClaudeChatItem(id: "u1", role: .user, content: "Q1", timestamp: Date()),
            ClaudeChatItem(id: "u2", role: .user, content: "Q2", timestamp: Date()),
            ClaudeChatItem(id: "a1", role: .assistant, content: "A", timestamp: Date()),
        ]
        let turns = ConversationTurn.group(items)
        XCTAssertEqual(turns.count, 2)
        XCTAssertEqual(turns[0].question?.content, "Q1")
        XCTAssertTrue(turns[0].replies.isEmpty)
        XCTAssertEqual(turns[1].question?.content, "Q2")
        XCTAssertEqual(turns[1].replies.count, 1)
    }
}
