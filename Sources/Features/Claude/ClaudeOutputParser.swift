import Foundation

/// 解析终端原始文本输出为 Claude Code 结构化消息
/// 通过识别 Claude Code 终端输出的特征模式来分割消息
enum ClaudeOutputParser {

    /// 检测终端输出是否包含 Claude Code 会话
    static func isClaudeSession(_ lines: [String]) -> Bool {
        let joinedPrefix = lines.prefix(30).joined(separator: "\n")
        return joinedPrefix.contains("Claude Code")
            || joinedPrefix.contains("Opus")
            || joinedPrefix.contains("Sonnet")
            || joinedPrefix.contains("claude>")
            || joinedPrefix.contains("╭") // Claude Code TUI 边框
            || joinedPrefix.contains("❯") // Claude prompt
    }

    /// 将终端行解析为 Claude 消息列表
    static func parse(_ lines: [String]) -> [ClaudeMessage] {
        var messages: [ClaudeMessage] = []
        var currentBlock: [String] = []
        var currentKind: ClaudeMessageKind = .systemEvent
        var blockIndex = 0

        // 过滤掉空白行和控制字符
        let cleanLines = lines.map { stripControlChars($0) }

        for line in cleanLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 跳过完全空白的行（但保留段落间距）
            if trimmed.isEmpty {
                if !currentBlock.isEmpty {
                    currentBlock.append("")
                }
                continue
            }

            // 检测用户输入行（以 > 或 ❯ 开头的 prompt）
            if isUserPrompt(trimmed) {
                // 保存之前的块
                if !currentBlock.isEmpty {
                    messages.append(makeMessage(kind: currentKind, lines: currentBlock, index: &blockIndex))
                    currentBlock = []
                }
                let userText = extractUserInput(trimmed)
                if !userText.isEmpty {
                    messages.append(ClaudeMessage(
                        id: "msg-\(blockIndex)",
                        kind: .userText,
                        content: userText,
                        timestamp: Date()
                    ))
                    blockIndex += 1
                }
                currentKind = .agentText
                continue
            }

            // 检测工具调用开始（常见模式）
            if isToolCallLine(trimmed) {
                if !currentBlock.isEmpty {
                    messages.append(makeMessage(kind: currentKind, lines: currentBlock, index: &blockIndex))
                    currentBlock = []
                }
                let (toolName, toolContent) = parseToolCall(trimmed)
                currentKind = .toolCall
                currentBlock = [toolContent]
                // 如果是单行工具调用，立即生成消息
                if isCompletedToolLine(trimmed) {
                    var msg = makeMessage(kind: .toolCall, lines: currentBlock, index: &blockIndex)
                    msg.toolName = toolName
                    msg.toolState = .completed
                    messages.append(msg)
                    currentBlock = []
                    currentKind = .agentText
                }
                continue
            }

            // 检测状态栏信息
            if isStatusLine(trimmed) {
                if !currentBlock.isEmpty {
                    messages.append(makeMessage(kind: currentKind, lines: currentBlock, index: &blockIndex))
                    currentBlock = []
                }
                currentKind = .systemEvent
                currentBlock = [trimmed]
                messages.append(makeMessage(kind: .systemEvent, lines: currentBlock, index: &blockIndex))
                currentBlock = []
                currentKind = .agentText
                continue
            }

            // 检测思考状态
            if trimmed.contains("Thinking") || trimmed.contains("thinking") {
                if !currentBlock.isEmpty {
                    messages.append(makeMessage(kind: currentKind, lines: currentBlock, index: &blockIndex))
                    currentBlock = []
                }
                messages.append(ClaudeMessage(
                    id: "msg-\(blockIndex)",
                    kind: .thinking,
                    content: trimmed,
                    timestamp: Date()
                ))
                blockIndex += 1
                currentKind = .agentText
                continue
            }

            // 普通文本行
            currentBlock.append(trimmed)
        }

        // 处理最后一个块
        if !currentBlock.isEmpty {
            messages.append(makeMessage(kind: currentKind, lines: currentBlock, index: &blockIndex))
        }

        return messages
    }

    /// 提取会话状态信息
    static func parseSessionStatus(_ lines: [String]) -> ClaudeSessionStatus {
        var status = ClaudeSessionStatus()
        let joined = lines.joined(separator: " ")

        // 检测模型信息
        if joined.contains("Opus") {
            status.model = "Claude Opus"
        } else if joined.contains("Sonnet") {
            status.model = "Claude Sonnet"
        } else if joined.contains("Haiku") {
            status.model = "Claude Haiku"
        }

        // 检测上下文用量
        if let range = joined.range(of: "Context ") {
            let after = String(joined[range.upperBound...])
            let contextPart = after.prefix(30).trimmingCharacters(in: .whitespaces)
            status.contextUsage = String(contextPart.prefix(while: { $0 != "\n" && $0 != "|" }))
        }

        status.isActive = joined.contains("claude>") || joined.contains("❯") || joined.contains("Claude Code")
        return status
    }

    // MARK: - 私有辅助方法

    /// 去除控制字符和 PUA 字符
    private static func stripControlChars(_ line: String) -> String {
        var result = ""
        for char in line {
            guard let scalar = char.unicodeScalars.first else { continue }
            let v = scalar.value
            // 跳过控制字符（保留空格、换行、制表符）
            if v < 0x20 && v != 0x0A && v != 0x0D && v != 0x09 { continue }
            // 跳过 PUA 字符
            if (v >= 0xE000 && v <= 0xF8FF) || (v >= 0xF0000 && v <= 0x10FFFD) { continue }
            result.append(char)
        }
        return result
    }

    /// 判断是否为用户输入行
    private static func isUserPrompt(_ line: String) -> Bool {
        // Claude Code 的 prompt 通常以 > 或 ❯ 开头
        return line.hasPrefix("> ") || line.hasPrefix("❯ ") || line.hasPrefix("claude> ")
    }

    /// 从 prompt 行提取用户输入
    private static func extractUserInput(_ line: String) -> String {
        if line.hasPrefix("claude> ") { return String(line.dropFirst(8)) }
        if line.hasPrefix("> ") { return String(line.dropFirst(2)) }
        if line.hasPrefix("❯ ") { return String(line.dropFirst(2)) }
        return line
    }

    /// 判断是否为工具调用行
    private static func isToolCallLine(_ line: String) -> Bool {
        let toolPatterns = [
            "Read(", "Write(", "Edit(", "Bash(",
            "Grep(", "Glob(", "Read file:", "Write file:",
            "Execute:", "Running:", "$ ",
        ]
        return toolPatterns.contains { line.contains($0) }
    }

    /// 判断工具调用是否已完成（单行结果）
    private static func isCompletedToolLine(_ line: String) -> Bool {
        return line.contains("✓") || line.contains("✗") || line.contains("Done")
    }

    /// 解析工具调用名称和内容
    private static func parseToolCall(_ line: String) -> (name: String, content: String) {
        if line.contains("Read(") || line.contains("Read file:") {
            return ("Read", line)
        } else if line.contains("Write(") || line.contains("Write file:") {
            return ("Write", line)
        } else if line.contains("Edit(") {
            return ("Edit", line)
        } else if line.contains("Bash(") || line.contains("$ ") || line.contains("Execute:") || line.contains("Running:") {
            return ("Bash", line)
        } else if line.contains("Grep(") {
            return ("Grep", line)
        } else if line.contains("Glob(") {
            return ("Glob", line)
        }
        return ("Tool", line)
    }

    /// 判断是否为状态栏行
    private static func isStatusLine(_ line: String) -> Bool {
        return line.contains("Context") && (line.contains("%") || line.contains("token"))
            || line.contains("Opus") && line.contains("context")
            || line.contains("Sonnet") && line.contains("context")
    }

    /// 从行数组构建消息
    private static func makeMessage(kind: ClaudeMessageKind, lines: [String], index: inout Int) -> ClaudeMessage {
        let content = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        let msg = ClaudeMessage(
            id: "msg-\(index)",
            kind: kind,
            content: content,
            timestamp: Date()
        )
        index += 1
        return msg
    }
}
