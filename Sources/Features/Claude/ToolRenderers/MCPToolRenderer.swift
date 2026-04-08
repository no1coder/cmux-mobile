import SwiftUI

/// MCP 工具渲染器 — 解析 mcp__server__tool 格式并以拼图图标展示
struct MCPToolRenderer: View {
    let name: String
    let input: String
    let result: String?
    let state: ClaudeChatItem.ToolState

    /// 解析 MCP 工具名称格式：mcp__server__tool → (server, tool)
    private var parsedName: (server: String, tool: String) {
        let parts = name.components(separatedBy: "__")
        guard parts.count >= 3 else {
            return (server: "MCP", tool: name)
        }
        // mcp__serverName__toolName
        let server = parts[1]
        let tool = parts.dropFirst(2).joined(separator: "__")
        return (server: server, tool: tool)
    }

    /// 格式化显示名称
    private var displayName: String {
        let parsed = parsedName
        return "MCP: \(parsed.server.capitalized) \u{2022} \(parsed.tool)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // MCP 工具名称标题
            HStack(spacing: 6) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 12))
                    .foregroundStyle(.indigo)
                Text(displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }

            // 使用 GenericToolView 展示输入/输出
            GenericToolView(
                name: name,
                input: input,
                result: result,
                state: state
            )
        }
    }
}
