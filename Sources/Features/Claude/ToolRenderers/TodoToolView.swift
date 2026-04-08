import SwiftUI

/// TodoWrite 工具渲染器 - 清单样式展示
struct TodoToolView: View {
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 标题
            HStack(spacing: 6) {
                Image(systemName: "checklist")
                    .font(.system(size: 13))
                    .foregroundStyle(.purple)
                Text("任务清单")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(.horizontal, 16)

            // 解析待办项
            let items = parseTodoItems()
            if !items.isEmpty {
                todoList(items)
            } else {
                // 回退到原始文本
                Text(input)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.horizontal, 16)
            }
        }
    }

    private func todoList(_ items: [TodoItem]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                HStack(alignment: .top, spacing: 8) {
                    Text(item.statusIcon)
                        .font(.system(size: 14))
                    Text(item.content)
                        .font(.system(size: 12))
                        .foregroundStyle(item.statusColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(item.backgroundColor)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 12)
    }

    /// 从输入 JSON 解析待办项
    private func parseTodoItems() -> [TodoItem] {
        guard let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let todos = json["todos"] as? [[String: Any]] else {
            return []
        }

        return todos.compactMap { dict in
            guard let content = dict["content"] as? String else { return nil }
            let status = dict["status"] as? String ?? "pending"
            return TodoItem(content: content, status: status)
        }
    }
}

/// 单个待办项
private struct TodoItem {
    let content: String
    let status: String

    var statusIcon: String {
        switch status {
        case "completed": return "\u{2611}" // ☑
        case "in_progress": return "\u{1F504}" // 🔄
        default: return "\u{2610}" // ☐
        }
    }

    var statusColor: Color {
        switch status {
        case "completed": return .green.opacity(0.7)
        case "in_progress": return .orange.opacity(0.8)
        default: return .white.opacity(0.6)
        }
    }

    var backgroundColor: Color {
        switch status {
        case "completed": return .green.opacity(0.04)
        case "in_progress": return .orange.opacity(0.04)
        default: return .clear
        }
    }
}
