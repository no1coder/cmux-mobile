import Testing
import Foundation
@testable import cmux_mobile

@Suite("ClaudeOutputParser Tests")
struct ClaudeOutputParserTests {

    // MARK: - isClaudeSession 测试

    @Test("检测 Claude TUI 活跃会话")
    func detectsClaudeSession() {
        // 模拟 Claude TUI 末尾的状态栏和边框
        let lines = [
            "Some output line",
            "Another line",
            "│ Hello from Claude",
            "╰─────────────────────────────────────────╯",
            "  Context: 42%    Opus (1M)    ~/my-project",
        ]
        let result = ClaudeOutputParser.isClaudeSession(lines)
        #expect(result == true)
    }

    @Test("非 Claude 终端返回 false")
    func rejectsNonClaudeSession() {
        let lines = [
            "$ ls -la",
            "total 42",
            "drwxr-xr-x  5 user group 160 Jan 1 00:00 .",
            "$ echo hello",
            "hello",
        ]
        let result = ClaudeOutputParser.isClaudeSession(lines)
        #expect(result == false)
    }

    @Test("空行列表返回 false")
    func emptyLinesReturnsFalse() {
        #expect(ClaudeOutputParser.isClaudeSession([]) == false)
    }

    // MARK: - parseSessionInfo 测试

    @Test("解析模型名称 - Opus")
    func parseModelOpus() {
        let lines = [
            "╭─────────────────────────────────────────╮",
            "│ Some content",
            "╰─────────────────────────────────────────╯",
            "  Opus (1M)    Context: 42%    ~/my-project",
        ]
        let info = ClaudeOutputParser.parseSessionInfo(lines)
        #expect(info.model.contains("Opus"))
    }

    @Test("解析模型名称 - Sonnet")
    func parseModelSonnet() {
        let lines = [
            "  Sonnet    Context: 15%    ~/another-project",
        ]
        let info = ClaudeOutputParser.parseSessionInfo(lines)
        #expect(info.model.contains("Sonnet"))
    }

    @Test("解析项目路径")
    func parseProjectPath() {
        let lines = [
            "~/code/my-awesome-project",
            "  Context: 42%    Opus (1M)",
        ]
        let info = ClaudeOutputParser.parseSessionInfo(lines)
        #expect(info.project.contains("~/"))
    }

    @Test("解析 Context 百分比")
    func parseContextPercentage() {
        let lines = [
            "  Context: 75%    Opus (1M)    ~/project",
        ]
        let info = ClaudeOutputParser.parseSessionInfo(lines)
        #expect(info.context.contains("%"))
    }

    @Test("无匹配信息返回空字符串")
    func parseEmptyReturnsEmpty() {
        let lines = ["just a normal line", "nothing special here"]
        let info = ClaudeOutputParser.parseSessionInfo(lines)
        #expect(info.model.isEmpty)
    }

    // MARK: - extractMessages 测试

    @Test("提取用户消息")
    func extractUserMessage() {
        let lines = [
            "> hello world",
            "",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let userMsgs = messages.filter { $0.kind == .userText }
        #expect(userMsgs.count >= 1)
        if let first = userMsgs.first {
            #expect(first.content.contains("hello world"))
        }
    }

    @Test("提取工具调用")
    func extractToolCall() {
        let lines = [
            "  Read(src/main.swift) ✓",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let toolMsgs = messages.filter { $0.kind == .toolCall }
        #expect(toolMsgs.count >= 1)
    }

    @Test("提取助手文本")
    func extractAgentText() {
        let lines = [
            "I'll help you with that. Let me check the code.",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let agentMsgs = messages.filter { $0.kind == .agentText }
        #expect(agentMsgs.count >= 1)
    }

    @Test("空行列表返回空数组")
    func emptyLinesReturnsEmpty() {
        let messages = ClaudeOutputParser.extractMessages([])
        #expect(messages.isEmpty)
    }

    @Test("过滤 TUI 装饰行")
    func filtersTUIDecoration() {
        // 纯装饰行（高比例装饰字符）不应生成消息
        let lines = [
            "╭──────────────────────────────────────╮",
            "├──────────────────────────────────────┤",
            "╰──────────────────────────────────────╯",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let agentMsgs = messages.filter { $0.kind == .agentText }
        #expect(agentMsgs.isEmpty)
    }

    @Test("完成的工具调用标记为 completed")
    func completedToolState() {
        let lines = [
            "  Read(package.json) ✓",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let toolMsgs = messages.filter { $0.kind == .toolCall }
        if let tool = toolMsgs.first {
            #expect(tool.toolState == .completed)
        }
    }

    @Test("失败的工具调用标记为 error")
    func errorToolState() {
        let lines = [
            "  Write(missing.txt) ✗",
        ]
        let messages = ClaudeOutputParser.extractMessages(lines)
        let toolMsgs = messages.filter { $0.kind == .toolCall }
        if let tool = toolMsgs.first {
            #expect(tool.toolState == .error)
        }
    }
}
