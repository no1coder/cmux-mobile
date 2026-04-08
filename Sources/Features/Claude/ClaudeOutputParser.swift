import Foundation

/// 解析终端原始文本输出，提取有意义的内容
/// 过滤掉所有 TUI 装饰（边框、ASCII 艺术、状态栏等）
enum ClaudeOutputParser {

    /// 检测终端输出是否包含 Claude Code 会话
    static func isClaudeSession(_ lines: [String]) -> Bool {
        let joined = lines.prefix(40).joined(separator: " ")
        return joined.contains("Claude Code")
            || joined.contains("Opus")
            || joined.contains("Sonnet")
    }

    /// 从终端输出中提取 Claude 会话信息
    static func parseSessionInfo(_ lines: [String]) -> (model: String, project: String, context: String) {
        var model = ""
        var project = ""
        var context = ""

        for line in lines {
            let clean = stripAll(line)
            if clean.isEmpty { continue }

            // 模型信息
            if clean.contains("Opus") && model.isEmpty {
                model = "Opus"
                if clean.contains("1M") { model += " (1M)" }
            } else if clean.contains("Sonnet") && model.isEmpty {
                model = "Sonnet"
            } else if clean.contains("Haiku") && model.isEmpty {
                model = "Haiku"
            }

            // 项目路径（~/开头）
            if clean.hasPrefix("~/") && project.isEmpty {
                project = clean
            }

            // 上下文用量
            if clean.contains("Context") && clean.contains("%") {
                // 提取百分比
                if let range = clean.range(of: #"\d+%"#, options: .regularExpression) {
                    context = String(clean[range])
                }
            }
        }

        return (model, project, context)
    }

    /// 从终端输出提取对话内容（过滤所有 TUI 装饰）
    static func extractMessages(_ lines: [String]) -> [ClaudeMessage] {
        var messages: [ClaudeMessage] = []
        var currentBlock: [String] = []
        var isInResponse = false
        var msgIndex = 0

        for line in lines {
            let clean = stripAll(line)

            // 跳过 TUI 装饰行
            if isTUIDecoration(clean) { continue }
            // 跳过空行（但在响应中保留段落间隔）
            if clean.isEmpty {
                if isInResponse && !currentBlock.isEmpty {
                    currentBlock.append("")
                }
                continue
            }
            // 跳过 Claude Code 启动信息
            if isStartupInfo(clean) { continue }
            // 跳过状态栏信息
            if isStatusBar(clean) { continue }

            // 检测用户输入（以 ❯ 或 > 开头的 prompt 行）
            if isPromptLine(clean) {
                // 保存之前的块
                if !currentBlock.isEmpty && isInResponse {
                    let content = currentBlock.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        messages.append(ClaudeMessage(
                            id: "msg-\(msgIndex)",
                            kind: .agentText,
                            content: content,
                            timestamp: Date()
                        ))
                        msgIndex += 1
                    }
                    currentBlock = []
                }

                let userInput = extractPromptInput(clean)
                if !userInput.isEmpty {
                    messages.append(ClaudeMessage(
                        id: "msg-\(msgIndex)",
                        kind: .userText,
                        content: userInput,
                        timestamp: Date()
                    ))
                    msgIndex += 1
                    isInResponse = true
                }
                continue
            }

            // 检测工具调用
            if let toolMsg = parseToolLine(clean, index: &msgIndex) {
                // 先保存之前的文本块
                if !currentBlock.isEmpty {
                    let content = currentBlock.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                    if !content.isEmpty {
                        messages.append(ClaudeMessage(
                            id: "msg-\(msgIndex)",
                            kind: .agentText,
                            content: content,
                            timestamp: Date()
                        ))
                        msgIndex += 1
                    }
                    currentBlock = []
                }
                messages.append(toolMsg)
                continue
            }

            // 普通文本内容
            currentBlock.append(clean)
            isInResponse = true
        }

        // 处理最后一个块
        if !currentBlock.isEmpty {
            let content = currentBlock.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !content.isEmpty {
                messages.append(ClaudeMessage(
                    id: "msg-\(msgIndex)",
                    kind: .agentText,
                    content: content,
                    timestamp: Date()
                ))
            }
        }

        return messages
    }

    // MARK: - 字符串清理

    /// 去除所有控制字符、ANSI 转义码、PUA 字符
    private static func stripAll(_ line: String) -> String {
        var result = ""
        var i = line.startIndex

        while i < line.endIndex {
            let char = line[i]

            // 跳过 ESC 序列
            if char == "\u{1B}" {
                i = line.index(after: i)
                guard i < line.endIndex else { break }
                let next = line[i]
                if next == "[" {
                    // CSI 序列：跳到终止符
                    i = line.index(after: i)
                    while i < line.endIndex {
                        let c = line[i]
                        if c.asciiValue.map({ $0 >= 0x40 && $0 <= 0x7E }) == true {
                            i = line.index(after: i)
                            break
                        }
                        i = line.index(after: i)
                    }
                } else if next == "]" {
                    // OSC 序列：跳到 BEL 或 ST
                    i = line.index(after: i)
                    while i < line.endIndex {
                        if line[i] == "\u{07}" { i = line.index(after: i); break }
                        if line[i] == "\u{1B}" {
                            let ni = line.index(after: i)
                            if ni < line.endIndex && line[ni] == "\\" {
                                i = line.index(after: ni)
                                break
                            }
                        }
                        i = line.index(after: i)
                    }
                } else {
                    i = line.index(after: i)
                }
                continue
            }

            // 跳过控制字符
            if let ascii = char.asciiValue, ascii < 0x20, ascii != 0x09 {
                i = line.index(after: i)
                continue
            }

            // 跳过 PUA 字符
            if let scalar = char.unicodeScalars.first {
                let v = scalar.value
                if (v >= 0xE000 && v <= 0xF8FF) || (v >= 0xF0000) {
                    i = line.index(after: i)
                    continue
                }
            }

            result.append(char)
            i = line.index(after: i)
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 判断是否为 TUI 装饰行（边框、分隔线等）
    private static func isTUIDecoration(_ line: String) -> Bool {
        if line.isEmpty { return false }

        // 计算装饰字符占比
        let decorChars: Set<Character> = ["─", "━", "═", "│", "┃", "║",
            "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘",
            "├", "┤", "┬", "┴", "┼", "╔", "╗", "╚", "╝",
            "▀", "▄", "█", "▐", "▌", "░", "▒", "▓",
            "╶", "╴", "╵", "╷", "─", "━"]

        let decorCount = line.filter { decorChars.contains($0) }.count
        let totalChars = line.count

        // 超过 50% 是装饰字符就跳过
        if totalChars > 0 && Double(decorCount) / Double(totalChars) > 0.5 {
            return true
        }

        // 全是横线/下划线
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.allSatisfy({ $0 == "─" || $0 == "━" || $0 == "_" || $0 == "=" || $0 == "-" }) && trimmed.count > 3 {
            return true
        }

        return false
    }

    /// 判断是否为 Claude Code 启动信息
    private static func isStartupInfo(_ line: String) -> Bool {
        return line.contains("Claude Code v")
            || line.contains("with medium effort")
            || line.contains("with high effort")
            || line.contains("Claude Max")
            || line.contains("Claude API")
            || line.contains("Loamwaddle")
            || line.contains("<(")  // ASCII 艺术
            || line.contains("._>") // ASCII 艺术
            || line.contains("`--'") // ASCII 艺术
            || line.contains("\\^^^/") // ASCII 艺术
    }

    /// 判断是否为状态栏
    private static func isStatusBar(_ line: String) -> Bool {
        return (line.contains("Context") && (line.contains("%") || line.contains("token")))
            || (line.contains("Opus") && line.contains("context"))
            || (line.contains("Sonnet") && line.contains("context"))
            || line.hasPrefix("[Opus") || line.hasPrefix("[Sonnet") || line.hasPrefix("[Haiku")
            || line.contains("git:(")
    }

    /// 判断是否为 prompt 行
    private static func isPromptLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("> ") || trimmed.hasPrefix("> ")
            || trimmed == ">" || trimmed == ">"
    }

    /// 从 prompt 行提取用户输入
    private static func extractPromptInput(_ line: String) -> String {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("> ") { return String(trimmed.dropFirst(2)) }
        if trimmed.hasPrefix("> ") { return String(trimmed.dropFirst(2)) }
        if trimmed == ">" || trimmed == ">" { return "" }
        return ""
    }

    /// 尝试解析工具调用行
    private static func parseToolLine(_ line: String, index: inout Int) -> ClaudeMessage? {
        let toolPatterns: [(pattern: String, name: String)] = [
            ("Read(", "Read"),
            ("Write(", "Write"),
            ("Edit(", "Edit"),
            ("Bash(", "Bash"),
            ("Grep(", "Grep"),
            ("Glob(", "Glob"),
            ("WebSearch(", "WebSearch"),
            ("WebFetch(", "WebFetch"),
            ("Agent(", "Agent"),
        ]

        for (pattern, name) in toolPatterns {
            if line.contains(pattern) {
                let msg = ClaudeMessage(
                    id: "msg-\(index)",
                    kind: .toolCall,
                    content: line,
                    timestamp: Date(),
                    toolName: name,
                    toolState: line.contains("✓") ? .completed : (line.contains("✗") ? .error : .running)
                )
                index += 1
                return msg
            }
        }

        return nil
    }
}
