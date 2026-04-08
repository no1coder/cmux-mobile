import Foundation

/// Claude Code 会话模型，用于会话管理和项目分组
struct ClaudeSession: Identifiable, Codable, Equatable {
    /// 会话唯一 ID（来自 JSONL session ID 或 surface ID）
    let id: String
    /// 关联的终端 surface ID
    let surfaceID: String
    /// 会话标题（通常为项目路径）
    var title: String
    /// 项目完整路径（如 ~/code/myproject）
    var projectPath: String
    /// 使用的模型（如 claude-sonnet-4-20250514）
    var model: String
    /// 创建时间
    let createdAt: Date
    /// 最后活跃时间
    var lastActiveAt: Date
    /// 是否已归档
    var isArchived: Bool

    /// 从路径提取项目名（最后一段路径）
    var projectName: String {
        projectPath.split(separator: "/").last.map(String.init) ?? projectPath
    }

    init(
        id: String,
        surfaceID: String,
        title: String,
        projectPath: String,
        model: String,
        createdAt: Date = Date(),
        lastActiveAt: Date = Date(),
        isArchived: Bool = false
    ) {
        self.id = id
        self.surfaceID = surfaceID
        self.title = title
        self.projectPath = projectPath
        self.model = model
        self.createdAt = createdAt
        self.lastActiveAt = lastActiveAt
        self.isArchived = isArchived
    }
}
