import SwiftUI
import UIKit

// MARK: - TUI 输出抓取与清洗

/// 仅在终端 TUI 中渲染输出的斜杠命令集合
/// 这些命令执行后不会在 JSONL 中产生消息，聊天视图自然不会显示内容
enum ClaudeChatTUI {
    static let tuiOnlyCommands: Set<String> = [
        "/status", "/help", "/cost", "/config", "/model", "/clear",
        "/memory", "/doctor", "/bug", "/mcp", "/hooks", "/agents",
        "/permissions", "/add-dir", "/ide", "/release-notes", "/vim",
        "/terminal-setup", "/init", "/review", "/logout", "/login",
        "/privacy-settings", "/upgrade", "/export", "/todos",
    ]

    static func isTUIOnlyCommand(_ text: String) -> Bool {
        guard text.hasPrefix("/") else { return false }
        let head = text.components(separatedBy: .whitespaces).first ?? text
        return tuiOnlyCommands.contains(head)
    }

    /// 清洗终端屏幕文本：去除 ANSI 转义、TUI 边框字符、多余空白；
    /// 尽量剔除 Claude Code 聊天 UI 本身的装饰（输入框、快捷键提示），
    /// 只保留 /status 等命令真正输出的内容
    static func cleanTUIOutput(_ lines: [String], command: String) -> String {
        // 去 ANSI 转义
        let ansi = try? NSRegularExpression(pattern: "\u{1b}\\[[0-9;?]*[a-zA-Z]")
        // 边框/盒线/半格字符
        let boxChars = Set<Character>(
            "─│┌┐└┘├┤┬┴┼━┃┏┓┗┛┣┫┳┻╋═║╔╗╚╝╠╣╦╩╬▌▐▀▄╭╮╰╯▲▼◀▶"
        )
        // 装饰性/状态栏字符
        let decoPrefixes: [String] = ["✳", "⏵", "❯", "›", "⎿", "▸", "▲", "▼"]
        // 明显属于输入框或快捷键提示的行
        let noisePatterns: [String] = [
            "Esc to cancel", "Tab to amend", "ctrl+e to explain",
            "to approve", "to reject", "to exit", "Shift+Tab",
            "? for shortcuts", "input?", "Type your message",
        ]

        var result: [String] = []
        for raw in lines {
            var s = raw
            if let regex = ansi {
                let range = NSRange(s.startIndex..., in: s)
                s = regex.stringByReplacingMatches(in: s, range: range, withTemplate: "")
            }
            s = String(s.filter { !boxChars.contains($0) })
            s = s.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else {
                if result.last?.isEmpty == false { result.append("") }
                continue
            }
            if decoPrefixes.contains(where: { s.hasPrefix($0) }) {
                s = String(s.dropFirst()).trimmingCharacters(in: .whitespaces)
                if s.isEmpty { continue }
            }
            if noisePatterns.contains(where: { s.localizedCaseInsensitiveContains($0) }) {
                continue
            }
            result.append(s)
        }
        while result.last?.isEmpty == true { result.removeLast() }
        while result.first?.isEmpty == true { result.removeFirst() }
        var deduped: [String] = []
        for line in result {
            if deduped.last != line { deduped.append(line) }
        }
        return deduped.joined(separator: "\n")
    }

    /// 从终端屏幕行中提取 Claude 正在输出的文本内容
    /// 跳过 TUI 框架元素（状态栏、工具调用指示器等），提取纯文本
    static func extractClaudeOutput(from lines: [String]) -> String {
        var contentLines: [String] = []
        var foundContent = false

        // 从倒数第二行开始（最后一行通常是输入框/快捷键提示）
        let scanLines = Array(lines.dropLast(2).reversed())

        for line in scanLines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                if foundContent { break }
                continue
            }

            // 跳过 TUI 装饰行（进度条、状态指示、分隔符等）
            if trimmed.hasPrefix("─") || trimmed.hasPrefix("━")
                || trimmed.hasPrefix("╭") || trimmed.hasPrefix("╰")
                || trimmed.hasPrefix("│") || trimmed.hasPrefix("┃")
                || trimmed.hasPrefix(">")
                || trimmed.hasPrefix("⏵")
                || trimmed.hasPrefix("●") || trimmed.hasPrefix("○")
            {
                if foundContent { break }
                continue
            }

            foundContent = true
            contentLines.append(trimmed)
        }

        contentLines.reverse()

        let joined = contentLines.joined(separator: "\n")
        if joined.count > 2000 {
            return String(joined.suffix(2000))
        }
        return joined
    }
}

// MARK: - TUI 抓屏 (ClaudeChatView 扩展)

extension ClaudeChatView {
    /// 发送 TUI-only 命令后从终端屏幕抓取输出，就地渲染为聊天气泡
    /// 策略：轮询 read_screen，等画面稳定后抓取，清洗 ANSI/TUI 边框字符后展示
    func captureTUIOutput(for command: String) {
        let placeholderId = "tui-\(UUID().uuidString)"
        // 先插入占位气泡，表示正在读取
        appendMessage(ClaudeChatItem(
            id: placeholderId,
            role: .tuiOutput(command: command),
            content: String(localized: "claude.tui.reading", defaultValue: "读取终端输出中…"),
            timestamp: Date()
        ))

        let task = Task { @MainActor in
            // 等一会让 TUI 渲染完成；再多轮读取直到画面稳定
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled else { return }
            var lastHash = 0
            var stableCount = 0
            var finalLines: [String] = []
            for attempt in 0..<8 {
                let lines = await readScreenLinesAsync()
                guard !Task.isCancelled else { return }
                let hash = lines.joined(separator: "\n").hashValue
                if hash == lastHash {
                    stableCount += 1
                } else {
                    stableCount = 0
                    lastHash = hash
                }
                finalLines = lines
                if stableCount >= 1 && attempt >= 1 { break }
                try? await Task.sleep(nanoseconds: 400_000_000)
                guard !Task.isCancelled else { return }
            }

            let cleaned = ClaudeChatTUI.cleanTUIOutput(finalLines, command: command)
            replaceTUIOutput(
                id: placeholderId,
                command: command,
                content: cleaned.isEmpty
                    ? String(localized: "claude.tui.empty",
                             defaultValue: "未能抓到 \(command) 的输出，点击聊天右上角菜单 →「查看终端」可直接查看")
                    : cleaned
            )
        }
        viewTaskBag.add(task)
    }

    func readScreenLinesAsync() async -> [String] {
        guard relayConnection.status == .connected else { return [] }
        return await withCheckedContinuation { cont in
            relayConnection.sendWithResponse([
                "method": "read_screen",
                "params": ["surface_id": surfaceID],
            ]) { result in
                let dict = result["result"] as? [String: Any] ?? result
                let lines = dict["lines"] as? [String] ?? []
                cont.resume(returning: lines)
            }
        }
    }

    /// 替换先前插入的占位 TUI 气泡
    func replaceTUIOutput(id: String, command: String, content: String) {
        var msgs = messageStore.claudeChats[surfaceID] ?? []
        guard let index = msgs.firstIndex(where: { $0.id == id }) else { return }
        msgs[index] = ClaudeChatItem(
            id: id,
            role: .tuiOutput(command: command),
            content: content,
            timestamp: msgs[index].timestamp
        )
        messageStore.setClaudeChat(surfaceID, messages: msgs)
    }
}
