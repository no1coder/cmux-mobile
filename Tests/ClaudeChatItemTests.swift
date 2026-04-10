import Testing
import Foundation
@testable import cmux_models

@Suite("ClaudeChatItem Tests")
struct ClaudeChatItemTests {

    // MARK: - 辅助方法

    private func makeItem(
        id: String = "msg-1",
        role: ClaudeChatItem.Role = .assistant,
        content: String = "hello",
        toolState: ClaudeChatItem.ToolState = .none,
        completedAt: Date? = nil,
        modelName: String? = nil
    ) -> ClaudeChatItem {
        ClaudeChatItem(
            id: id,
            role: role,
            content: content,
            timestamp: Date(),
            toolState: toolState,
            completedAt: completedAt,
            modelName: modelName
        )
    }

    // MARK: - Role 测试

    @Test("用户角色创建")
    func userRole() {
        let item = makeItem(role: .user, content: "question")
        #expect(item.role == .user)
    }

    @Test("助手角色创建")
    func assistantRole() {
        let item = makeItem(role: .assistant, content: "answer")
        #expect(item.role == .assistant)
    }

    @Test("thinking 角色创建")
    func thinkingRole() {
        let item = makeItem(role: .thinking, content: "reasoning...")
        #expect(item.role == .thinking)
    }

    @Test("tool 角色带名称")
    func toolRoleWithName() {
        let item = makeItem(role: .tool(name: "Read"), content: "file content")
        #expect(item.role == .tool(name: "Read"))
    }

    @Test("system 角色创建")
    func systemRole() {
        let item = makeItem(role: .system, content: "system msg")
        #expect(item.role == .system)
    }

    @Test("不同名称的 tool 角色不相等")
    func differentToolNamesNotEqual() {
        let role1 = ClaudeChatItem.Role.tool(name: "Read")
        let role2 = ClaudeChatItem.Role.tool(name: "Write")
        #expect(role1 != role2)
    }

    // MARK: - ToolState 测试

    @Test("ToolState 枚举值")
    func toolStates() {
        #expect(ClaudeChatItem.ToolState.running != .completed)
        #expect(ClaudeChatItem.ToolState.error != .none)
        #expect(ClaudeChatItem.ToolState.completed != .running)
    }

    // MARK: - 相等性测试

    @Test("相同 id/content/toolState 的 item 相等")
    func equalItems() {
        let item1 = ClaudeChatItem(
            id: "msg-1",
            role: .assistant,
            content: "hello",
            timestamp: Date(),
            toolState: .none
        )
        let item2 = ClaudeChatItem(
            id: "msg-1",
            role: .assistant,
            content: "hello",
            timestamp: Date().addingTimeInterval(100), // 不同时间戳
            toolState: .none,
            modelName: "Opus" // 额外字段
        )
        #expect(item1 == item2)
    }

    @Test("不同 id 的 item 不相等")
    func differentIdNotEqual() {
        let item1 = makeItem(id: "msg-1", content: "same")
        let item2 = makeItem(id: "msg-2", content: "same")
        #expect(item1 != item2)
    }

    @Test("不同 content 的 item 不相等")
    func differentContentNotEqual() {
        let item1 = makeItem(id: "msg-1", content: "aaa")
        let item2 = makeItem(id: "msg-1", content: "bbb")
        #expect(item1 != item2)
    }

    @Test("不同 toolState 的 item 不相等")
    func differentToolStateNotEqual() {
        let item1 = makeItem(id: "msg-1", toolState: .running)
        let item2 = makeItem(id: "msg-1", toolState: .completed)
        #expect(item1 != item2)
    }

    // MARK: - durationSeconds 测试

    @Test("有 completedAt 时计算 duration")
    func durationWithCompletedAt() {
        let start = Date()
        let end = start.addingTimeInterval(5.0)
        let item = ClaudeChatItem(
            id: "t1",
            role: .tool(name: "Bash"),
            content: "output",
            timestamp: start,
            toolState: .completed,
            completedAt: end
        )
        let duration = item.durationSeconds
        #expect(duration != nil)
        #expect(duration! >= 4.9 && duration! <= 5.1)
    }

    @Test("无 completedAt 时 duration 为 nil")
    func durationWithoutCompletedAt() {
        let item = makeItem(toolState: .running)
        #expect(item.durationSeconds == nil)
    }

    // MARK: - 可选字段测试

    @Test("modelName 默认为 nil")
    func modelNameDefaultNil() {
        let item = makeItem()
        #expect(item.modelName == nil)
    }

    @Test("modelName 可设置")
    func modelNameSet() {
        let item = makeItem(modelName: "Opus (1M)")
        #expect(item.modelName == "Opus (1M)")
    }

    @Test("toolUseId 链接工具调用和结果")
    func toolUseIdLinking() {
        let useItem = ClaudeChatItem(
            id: "use-1",
            role: .assistant,
            content: "calling tool",
            timestamp: Date(),
            toolState: .none,
            toolUseId: "tu-123"
        )
        let resultItem = ClaudeChatItem(
            id: "result-1",
            role: .tool(name: "Read"),
            content: "file content",
            timestamp: Date(),
            toolState: .completed,
            toolUseId: "tu-123"
        )
        #expect(useItem.toolUseId == resultItem.toolUseId)
    }
}
