import Foundation

/// 解析终端原始文本输出，提取有意义的内容
/// 过滤掉所有 TUI 装饰（边框、ASCII 艺术、状态栏等）
enum ClaudeOutputParser {

    /// 检测终端是否有 Claude Code 正在运行（而非历史残留输出）
    /// 检查终端最后几行是否有 Claude TUI 活跃特征：
    /// - 底部状态栏（Context/Usage 百分比行）
    /// - Claude 输入 prompt（❯ 或 >）紧接状态栏
    /// - box-drawing 边框（╭╮╰╯─）表示 TUI 正在渲染
    static func isClaudeSession(_ lines: [String]) -> Bool {
        // 只检查最后 15 行（活跃 TUI 特征只出现在底部）
        let tail = lines.suffix(15)
        let tailJoined = tail.joined(separator: " ")

        // 必须有 Claude TUI 状态栏特征（Context/Usage + 百分比）
        let hasStatusBar = tailJoined.contains("Context") && tailJoined.contains("%")
        // 必须有 box-drawing 边框（Claude TUI 的分隔线）
        let hasBoxDrawing = tail.contains { line in
            line.contains("─") || line.contains("╭") || line.contains("╰")
        }

        return hasStatusBar && hasBoxDrawing
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

            // 跳过 PUA 字符、盲文、方块元素
            if let scalar = char.unicodeScalars.first {
                let v = scalar.value
                if (v >= 0xE000 && v <= 0xF8FF)   // PUA
                    || (v >= 0xF0000)               // Supplementary PUA
                    || (v >= 0x2580 && v <= 0x259F) // Block Elements
                    || (v >= 0x2800 && v <= 0x28FF) // Braille
                    || (v >= 0x2500 && v <= 0x257F) // Box Drawing
                {
                    i = line.index(after: i)
                    continue
                }
            }

            result.append(char)
            i = line.index(after: i)
        }

        return result.trimmingCharacters(in: .whitespaces)
    }

    /// 判断是否为 TUI 装饰行或无意义内容
    private static func isTUIDecoration(_ line: String) -> Bool {
        if line.isEmpty { return false }
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return true }

        // 装饰字符集（边框、方块、盲文、箭头等）
        let decorChars: Set<Character> = [
            "─", "━", "═", "│", "┃", "║",
            "╭", "╮", "╰", "╯", "┌", "┐", "└", "┘",
            "├", "┤", "┬", "┴", "┼", "╔", "╗", "╚", "╝",
            "▀", "▄", "█", "▐", "▌", "░", "▒", "▓", "■", "□",
            "╶", "╴", "╵", "╷",
            "❯", "›", "❮", "‹", "▶", "◀", "▷", "◁",
            "⣿", "⣀", "⠀", "⠿", // 盲文字符
        ]

        let decorCount = trimmed.filter { decorChars.contains($0) }.count

        // 超过 40% 是装饰字符就跳过
        if trimmed.count > 0 && Double(decorCount) / Double(trimmed.count) > 0.4 {
            return true
        }

        // 极短且只有特殊字符（如单独的 ❯、_、>）
        if trimmed.count <= 3 {
            let meaningful = trimmed.filter { $0.isLetter || $0.isNumber }
            if meaningful.isEmpty { return true }
        }

        // 全是横线/下划线/等号
        if trimmed.allSatisfy({ "─━_=-~".contains($0) }) && trimmed.count > 2 {
            return true
        }

        return false
    }

    /// 判断是否为 Claude Code 启动信息或装饰内容
    private static func isStartupInfo(_ line: String) -> Bool {
        return line.contains("Claude Code v")
            || line.contains("with medium effort")
            || line.contains("with high effort")
            || line.contains("with low effort")
            || line.contains("Claude Max")
            || line.contains("Claude API")
            || line.contains("Loamwaddle")
            || line.contains("<(")
            || line.contains("._>")
            || line.contains("`--'")
            || line.contains("\\^^^/")
            || line.contains("^^^")
            || line.contains("1M context")
            || line.contains("200K context")
            || line.contains("Claude Pro")
            || line.contains("Accessing workspace")
            || line.contains("safety check")
            || line.contains("trust this folder")
            || line.contains("Security guide")
    }

    /// 判断是否为状态栏或元信息
    private static func isStatusBar(_ line: String) -> Bool {
        return (line.contains("Context") && (line.contains("%") || line.contains("token")))
            || (line.contains("Opus") && line.contains("context"))
            || (line.contains("Sonnet") && line.contains("context"))
            || line.hasPrefix("[Opus") || line.hasPrefix("[Sonnet") || line.hasPrefix("[Haiku")
            || line.contains("git:(")
            || line.contains("git:")
            || line.contains("main*)")
            || line.contains("main!?")
            || (line.contains("Opus") && line.contains("1M"))
            || (line.contains("Sonnet") && line.contains("200K"))
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
