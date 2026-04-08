import SwiftUI

/// 任务/代理层级树节点
struct TaskNode: Identifiable {
    let id: String
    let name: String
    let description: String
    let status: ClaudeChatItem.ToolState
    let children: [TaskNode]
}

/// 任务层级树视图：展示嵌套的代理/工具调用
struct TaskTreeView: View {
    let tasks: [TaskNode]

    var body: some View {
        List {
            ForEach(tasks) { task in
                TaskNodeRow(node: task, depth: 0)
            }
        }
        .listStyle(.plain)
        .navigationTitle(String(localized: "task_tree.title", defaultValue: "任务树"))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// 单个任务节点行（递归渲染子节点）
struct TaskNodeRow: View {
    let node: TaskNode
    let depth: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // 缩进
                if depth > 0 {
                    Color.clear.frame(width: CGFloat(depth) * 16)
                }

                // 状态图标
                statusIcon
                    .frame(width: 16, height: 16)

                Text(node.name)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)

                Spacer()
            }

            // 描述
            if !node.description.isEmpty {
                Text(node.description)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .padding(.leading, CGFloat(depth) * 16 + 22)
            }

            // 递归渲染子节点
            ForEach(node.children) { child in
                TaskNodeRow(node: child, depth: depth + 1)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - 状态图标

    @ViewBuilder
    private var statusIcon: some View {
        switch node.status {
        case .running:
            ProgressView()
                .scaleEffect(0.6)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.system(size: 13))
        case .error:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.system(size: 13))
        case .none:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
                .font(.system(size: 13))
        }
    }
}
