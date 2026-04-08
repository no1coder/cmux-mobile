import SwiftUI

/// 可复用 Diff 视图组件 — 红色标记删除行，绿色标记新增行
struct DiffCodeView: View {
    let oldText: String
    let newText: String
    var showLineNumbers: Bool = true

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(diffLines.enumerated()), id: \.offset) { index, line in
                    diffLineRow(line: line, lineNumber: index + 1)
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Diff 计算

    /// Diff 行类型
    private enum DiffLineKind {
        case removed  // 删除行（红色）
        case added    // 新增行（绿色）
        case context  // 上下文行（灰色）
    }

    private struct DiffLine {
        let kind: DiffLineKind
        let text: String
    }

    /// 简单 diff：旧文本标记为删除，新文本标记为新增
    private var diffLines: [DiffLine] {
        var result: [DiffLine] = []
        let oldLines = oldText.components(separatedBy: "\n")
        let newLines = newText.components(separatedBy: "\n")

        for line in oldLines where !oldText.isEmpty {
            result.append(DiffLine(kind: .removed, text: line))
        }
        for line in newLines where !newText.isEmpty {
            result.append(DiffLine(kind: .added, text: line))
        }
        return result
    }

    // MARK: - 行渲染

    private func diffLineRow(line: DiffLine, lineNumber: Int) -> some View {
        HStack(spacing: 0) {
            if showLineNumbers {
                Text("\(lineNumber)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.2))
                    .frame(width: 28, alignment: .trailing)
                    .padding(.trailing, 4)
            }

            Text(prefix(for: line.kind))
                .font(.system(size: 11, weight: .bold, design: .monospaced))
                .foregroundStyle(foregroundColor(for: line.kind))
                .frame(width: 14, alignment: .center)

            Text(line.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(foregroundColor(for: line.kind))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor(for: line.kind))
    }

    private func prefix(for kind: DiffLineKind) -> String {
        switch kind {
        case .removed: return "-"
        case .added: return "+"
        case .context: return " "
        }
    }

    private func foregroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .removed: return .red.opacity(0.8)
        case .added: return .green.opacity(0.8)
        case .context: return .white.opacity(0.4)
        }
    }

    private func backgroundColor(for kind: DiffLineKind) -> Color {
        switch kind {
        case .removed: return .red.opacity(0.15)
        case .added: return .green.opacity(0.15)
        case .context: return .clear
        }
    }
}
