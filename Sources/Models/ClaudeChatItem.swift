import Foundation

/// Claude 聊天消息项（持久化在 MessageStore 中）
struct ClaudeChatItem: Identifiable, Equatable, Codable {
    let id: String
    let seq: Int?
    let role: Role
    let content: String
    let timestamp: Date
    /// 工具执行结果（仅 tool 角色有值）
    let toolResult: String?
    /// 工具状态
    let toolState: ToolState
    /// 工具调用 ID（用于关联 tool_use 和 tool_result）
    let toolUseId: String?
    /// 工具完成时间（用于计算耗时）
    let completedAt: Date?
    /// 使用的模型名称（仅 assistant 消息有值）
    let modelName: String?

    enum Role: Equatable, Codable {
        case user
        case assistant
        case thinking  // Claude 的思考过程（extended thinking）
        case tool(name: String)
        case system
        /// TUI-only 命令（如 /status）的输出：从终端屏幕抓取后就地渲染
        case tuiOutput(command: String)

        private enum CodingKeys: String, CodingKey {
            case kind
            case name
            case command
        }

        private enum Kind: String, Codable {
            case user
            case assistant
            case thinking
            case tool
            case system
            case tuiOutput
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            switch try container.decode(Kind.self, forKey: .kind) {
            case .user:
                self = .user
            case .assistant:
                self = .assistant
            case .thinking:
                self = .thinking
            case .tool:
                self = .tool(name: try container.decode(String.self, forKey: .name))
            case .system:
                self = .system
            case .tuiOutput:
                self = .tuiOutput(command: try container.decode(String.self, forKey: .command))
            }
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .user:
                try container.encode(Kind.user, forKey: .kind)
            case .assistant:
                try container.encode(Kind.assistant, forKey: .kind)
            case .thinking:
                try container.encode(Kind.thinking, forKey: .kind)
            case .tool(let name):
                try container.encode(Kind.tool, forKey: .kind)
                try container.encode(name, forKey: .name)
            case .system:
                try container.encode(Kind.system, forKey: .kind)
            case .tuiOutput(let command):
                try container.encode(Kind.tuiOutput, forKey: .kind)
                try container.encode(command, forKey: .command)
            }
        }
    }

    enum ToolState: String, Equatable, Codable {
        case running
        case completed
        case error
        case none
    }

    init(id: String, seq: Int? = nil, role: Role, content: String, timestamp: Date,
         toolResult: String? = nil, toolState: ToolState = .none, toolUseId: String? = nil,
         completedAt: Date? = nil, modelName: String? = nil) {
        self.id = id
        self.seq = seq
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.toolResult = toolResult
        self.toolState = toolState
        self.toolUseId = toolUseId
        self.completedAt = completedAt
        self.modelName = modelName
    }

    /// 工具执行耗时（秒），仅已完成的工具有值
    var durationSeconds: Double? {
        guard let completed = completedAt else { return nil }
        return completed.timeIntervalSince(timestamp)
    }

    func withToolState(_ state: ToolState, completedAt newCompletedAt: Date?) -> ClaudeChatItem {
        ClaudeChatItem(
            id: id,
            seq: seq,
            role: role,
            content: content,
            timestamp: timestamp,
            toolResult: toolResult,
            toolState: state,
            toolUseId: toolUseId,
            completedAt: newCompletedAt,
            modelName: modelName
        )
    }

    /// 归一化工具状态：
    /// 只有尾部连续的 running 工具才允许继续显示为"执行中"；
    /// 一旦某个 running 工具后面已经出现了别的消息，说明 Claude 已经越过它，
    /// 即使缺少显式 tool_result，也应视为已完成，避免手机端长期卡在执行中。
    static func normalizeRunningTools(
        in messages: [ClaudeChatItem],
        allowTrailingRunningTools: Bool = true
    ) -> [ClaudeChatItem] {
        guard !messages.isEmpty else { return messages }

        var reversedNormalized: [ClaudeChatItem] = []
        reversedNormalized.reserveCapacity(messages.count)

        var canKeepTrailingRunningTools = allowTrailingRunningTools
        var completionMarkerDate: Date?

        for item in messages.reversed() {
            if case .tool = item.role, item.toolState == .running {
                if canKeepTrailingRunningTools {
                    reversedNormalized.append(item)
                } else {
                    let finishedAt = item.completedAt ?? completionMarkerDate ?? item.timestamp
                    reversedNormalized.append(item.withToolState(.completed, completedAt: finishedAt))
                }
                continue
            }

            canKeepTrailingRunningTools = false
            completionMarkerDate = item.completedAt ?? item.timestamp
            reversedNormalized.append(item)
        }

        return reversedNormalized.reversed()
    }

    static func == (lhs: ClaudeChatItem, rhs: ClaudeChatItem) -> Bool {
        lhs.id == rhs.id && lhs.content == rhs.content && lhs.toolState == rhs.toolState
    }
}
