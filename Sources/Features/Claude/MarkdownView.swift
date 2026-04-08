import SwiftUI

/// 简易 Markdown 渲染器，支持块级元素
/// 支持：# 标题、``` 代码块、--- 分隔线、- 列表、| 表格、行内样式
/// Equatable 使 SwiftUI 在 content 未变时跳过重新渲染
struct MarkdownView: View, Equatable {
    let content: String

    static func == (lhs: MarkdownView, rhs: MarkdownView) -> Bool {
        lhs.content == rhs.content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(parseBlocks().enumerated()), id: \.offset) { _, block in
                renderBlock(block)
            }
        }
    }

    // MARK: - 块级解析

    private enum Block {
        case heading(level: Int, text: String)
        case codeBlock(language: String, code: String)
        case horizontalRule
        case listItem(indent: Int, text: String)
        case tableRow(cells: [String], isHeader: Bool)
        case tableSeparator
        case paragraph(text: String)
    }

    private func parseBlocks() -> [Block] {
        var blocks: [Block] = []
        let lines = content.components(separatedBy: "\n")
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 代码块 ```
            if trimmed.hasPrefix("```") {
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var codeLines: [String] = []
                i += 1
                while i < lines.count {
                    if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                        i += 1
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                blocks.append(.codeBlock(language: language, code: codeLines.joined(separator: "\n")))
                continue
            }

            // 分隔线 ---
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                blocks.append(.horizontalRule)
                i += 1
                continue
            }

            // 标题 # ## ###
            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let text = String(trimmed.dropFirst(level)).trimmingCharacters(in: .whitespaces)
                if level <= 6 && !text.isEmpty {
                    blocks.append(.heading(level: level, text: text))
                    i += 1
                    continue
                }
            }

            // 表格分隔行 |---|---|
            if trimmed.hasPrefix("|") && trimmed.contains("---") {
                blocks.append(.tableSeparator)
                i += 1
                continue
            }

            // 表格行 | a | b |
            if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count > 2 {
                let cells = trimmed
                    .dropFirst().dropLast()
                    .components(separatedBy: "|")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                // 判断是否为表头（前面没有表格行，或后面紧跟分隔行）
                let isHeader = i + 1 < lines.count &&
                    lines[i + 1].trimmingCharacters(in: .whitespaces).contains("---")
                blocks.append(.tableRow(cells: cells, isHeader: isHeader))
                i += 1
                continue
            }

            // 列表项 - * 或数字.
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = line.prefix(while: { $0 == " " }).count / 2
                let text = String(trimmed.dropFirst(2))
                blocks.append(.listItem(indent: indent, text: text))
                i += 1
                continue
            }
            if let dotIdx = trimmed.firstIndex(of: "."),
               dotIdx > trimmed.startIndex,
               trimmed[trimmed.startIndex..<dotIdx].allSatisfy({ $0.isNumber }),
               trimmed.index(after: dotIdx) < trimmed.endIndex,
               trimmed[trimmed.index(after: dotIdx)] == " " {
                let text = String(trimmed[trimmed.index(dotIdx, offsetBy: 2)...])
                blocks.append(.listItem(indent: 0, text: text))
                i += 1
                continue
            }

            // 空行跳过
            if trimmed.isEmpty {
                i += 1
                continue
            }

            // 普通段落（合并连续非空行）
            var paraLines: [String] = [trimmed]
            i += 1
            while i < lines.count {
                let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                if nextTrimmed.isEmpty || nextTrimmed.hasPrefix("#") || nextTrimmed.hasPrefix("```")
                    || nextTrimmed.hasPrefix("---") || nextTrimmed.hasPrefix("- ")
                    || nextTrimmed.hasPrefix("* ") || nextTrimmed.hasPrefix("|") {
                    break
                }
                paraLines.append(nextTrimmed)
                i += 1
            }
            blocks.append(.paragraph(text: paraLines.joined(separator: "\n")))
        }

        return blocks
    }

    // MARK: - 块级渲染

    @ViewBuilder
    private func renderBlock(_ block: Block) -> some View {
        switch block {
        case .heading(let level, let text):
            renderHeading(level: level, text: text)

        case .codeBlock(_, let code):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.8))
                    .padding(10)
            }
            .background(Color.black.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: 6))

        case .horizontalRule:
            Rectangle()
                .fill(Color.white.opacity(0.1))
                .frame(height: 1)
                .padding(.vertical, 4)

        case .listItem(let indent, let text):
            HStack(alignment: .top, spacing: 6) {
                Text("•")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.4))
                    .padding(.leading, CGFloat(indent) * 16)
                inlineMarkdown(text)
            }

        case .tableRow(let cells, let isHeader):
            HStack(spacing: 0) {
                ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                    inlineMarkdown(cell)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .fontWeight(isHeader ? .semibold : .regular)
                }
            }
            .background(isHeader ? Color.white.opacity(0.04) : Color.clear)

        case .tableSeparator:
            EmptyView()

        case .paragraph(let text):
            inlineMarkdown(text)
        }
    }

    private func renderHeading(level: Int, text: String) -> some View {
        let fontSize: CGFloat = switch level {
        case 1: 22
        case 2: 19
        case 3: 16
        default: 15
        }
        return Text(text)
            .font(.system(size: fontSize, weight: .bold))
            .foregroundStyle(.white)
            .padding(.top, level <= 2 ? 8 : 4)
    }

    // MARK: - 行内 Markdown

    @ViewBuilder
    private func inlineMarkdown(_ text: String) -> some View {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            Text(attributed)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(.white.opacity(0.9))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
