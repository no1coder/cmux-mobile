import SwiftUI

/// 工具渲染器工厂 - 根据工具名返回专属渲染视图
enum ToolRendererFactory {
    @ViewBuilder
    static func renderer(
        name: String,
        input: String,
        result: String?,
        state: ClaudeChatItem.ToolState
    ) -> some View {
        switch name {
        case "Bash":
            BashToolView(input: input, result: result, state: state)
        case "Read":
            ReadToolView(input: input, result: result, state: state)
        case "Edit":
            EditToolView(input: input, result: result, state: state)
        case "Write":
            WriteToolView(input: input, result: result, state: state)
        case "Grep":
            GrepToolView(input: input, result: result, state: state)
        case "Glob":
            GlobToolView(input: input, result: result, state: state)
        case "TodoWrite":
            TodoToolView(input: input, result: result, state: state)
        default:
            GenericToolView(name: name, input: input, result: result, state: state)
        }
    }
}
