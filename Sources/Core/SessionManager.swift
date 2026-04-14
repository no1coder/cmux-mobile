import Combine
import Foundation
#if SWIFT_PACKAGE
import cmux_models
#endif

/// 管理 Claude Code 会话的持久化和同步
/// 使用 JSON 文件存储，避免 SwiftData 的 iOS 版本依赖
@MainActor
public final class SessionManager: ObservableObject {

    /// 所有会话（活跃 + 归档）
    @Published public private(set) var sessions: [ClaudeSession] = []

    /// JSON 存储路径
    private let storageURL: URL

    public init() {
        // 优先 Documents；极端情况下（例如系统沙箱异常）回退到 tmp 避免崩溃
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        storageURL = dir.appendingPathComponent("claude-sessions.json")
        sessions = Self.loadFromDisk(url: storageURL)
    }

    // MARK: - 公开接口

    /// 判断 surface 是否为 Claude Code 会话
    /// cmux 运行 Claude 时会把标题改成 "✳ ..." 或包含 "Claude Code"
    /// 注意：Claude 在工作中会临时把标题改成 "Fix..." 等摘要文本，
    /// 这类会话不会被此函数识别，需要由 TerminalDetailView 在检测到 Claude 模式时
    /// 调用 `markAsClaudeSession(surfaceID:)` 主动登记。
    public static func isClaudeSurface(_ surface: Surface) -> Bool {
        let title = surface.title
        if title.hasPrefix("✳") { return true }
        if title.contains("Claude Code") { return true }
        return false
    }

    /// 由 TerminalDetailView 在检测到 Claude 模式后主动登记，
    /// 避免因标题临时变化（例如 Claude 把标题改成摘要）导致会话从列表中消失
    public func markAsClaudeSession(surfaceID: String, title: String, cwd: String?) {
        var updated = sessions
        if let index = updated.firstIndex(where: { $0.surfaceID == surfaceID }) {
            let old = updated[index]
            // 仅修正会话元数据，不把模式检测/列表刷新误记成“最近活跃”
            let newTitle = title.isEmpty ? old.title : title
            let newPath = (cwd?.isEmpty == false ? cwd! : old.projectPath)
            let newSession = ClaudeSession(
                id: old.id,
                surfaceID: old.surfaceID,
                title: newTitle,
                projectPath: newPath,
                model: old.model,
                createdAt: old.createdAt,
                lastActiveAt: old.lastActiveAt,
                isArchived: false
            )
            guard newSession != old else { return }
            updated[index] = newSession
        } else {
            updated.append(ClaudeSession(
                id: "session-\(surfaceID)",
                surfaceID: surfaceID,
                title: title,
                projectPath: cwd ?? "",
                model: ""
            ))
        }
        sessions = updated
        saveToDisk()
    }

    /// 从当前 surface 列表同步会话数据
    /// 检测标题以 "✳" 开头或包含 "Claude Code" 的 surface，自动创建/更新会话
    public func syncFromSurfaces(_ surfaces: [Surface]) {
        var updated = sessions
        var changed = false

        for surface in surfaces where Self.isClaudeSurface(surface) {
            let projectPath = surface.cwd ?? surface.workspaceName ?? ""
            let sessionID = "session-\(surface.id)"

            if let index = updated.firstIndex(where: { $0.surfaceID == surface.id }) {
                // 只同步元数据，不把 surface.list 的轮询刷新误记成“最近活跃”
                let session = updated[index]
                let newSession = ClaudeSession(
                    id: session.id,
                    surfaceID: session.surfaceID,
                    title: surface.title,
                    projectPath: projectPath.isEmpty ? session.projectPath : projectPath,
                    model: session.model,
                    createdAt: session.createdAt,
                    lastActiveAt: session.lastActiveAt,
                    isArchived: false  // 重新出现则自动取消归档
                )
                if newSession != session {
                    updated[index] = newSession
                    changed = true
                }
            } else {
                // 新会话
                let session = ClaudeSession(
                    id: sessionID,
                    surfaceID: surface.id,
                    title: surface.title,
                    projectPath: projectPath,
                    model: ""
                )
                updated.append(session)
                changed = true
            }
        }

        // 自动归档：只有当 surface 本身从列表中消失时才归档
        // 不再因标题临时变化（例如 Claude 把标题改成 "Fix..." 摘要）而归档，
        // 避免 Claude 会话分组在工作中消失
        let allSurfaceIDs = Set(surfaces.map(\.id))
        for index in updated.indices {
            if !updated[index].isArchived && !allSurfaceIDs.contains(updated[index].surfaceID) {
                updated[index] = ClaudeSession(
                    id: updated[index].id,
                    surfaceID: updated[index].surfaceID,
                    title: updated[index].title,
                    projectPath: updated[index].projectPath,
                    model: updated[index].model,
                    createdAt: updated[index].createdAt,
                    lastActiveAt: updated[index].lastActiveAt,
                    isArchived: true
                )
                changed = true
            }
        }

        if changed {
            sessions = updated
            saveToDisk()
        }
    }

    /// 仅在真实消息/工具活动发生时刷新会话活跃时间
    public func touchActivity(surfaceID: String, at date: Date = Date()) {
        guard let index = sessions.firstIndex(where: { $0.surfaceID == surfaceID }) else { return }
        let session = sessions[index]
        guard date > session.lastActiveAt else { return }

        var updated = sessions
        updated[index] = ClaudeSession(
            id: session.id,
            surfaceID: session.surfaceID,
            title: session.title,
            projectPath: session.projectPath,
            model: session.model,
            createdAt: session.createdAt,
            lastActiveAt: date,
            isArchived: session.isArchived
        )
        sessions = updated
        saveToDisk()
    }

    /// 更新会话的模型信息（从 ClaudeChatView 的 session info 回传）
    public func updateModel(surfaceID: String, model: String) {
        guard let index = sessions.firstIndex(where: { $0.surfaceID == surfaceID }),
              !model.isEmpty,
              sessions[index].model != model else { return }
        var updated = sessions
        let old = updated[index]
        updated[index] = ClaudeSession(
            id: old.id,
            surfaceID: old.surfaceID,
            title: old.title,
            projectPath: old.projectPath,
            model: model,
            createdAt: old.createdAt,
            lastActiveAt: old.lastActiveAt,
            isArchived: old.isArchived
        )
        sessions = updated
        saveToDisk()
    }

    /// 归档指定会话
    public func archive(id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = sessions
        let old = updated[index]
        updated[index] = ClaudeSession(
            id: old.id,
            surfaceID: old.surfaceID,
            title: old.title,
            projectPath: old.projectPath,
            model: old.model,
            createdAt: old.createdAt,
            lastActiveAt: old.lastActiveAt,
            isArchived: true
        )
        sessions = updated
        saveToDisk()
    }

    /// 恢复归档会话
    public func restore(id: String) {
        guard let index = sessions.firstIndex(where: { $0.id == id }) else { return }
        var updated = sessions
        let old = updated[index]
        updated[index] = ClaudeSession(
            id: old.id,
            surfaceID: old.surfaceID,
            title: old.title,
            projectPath: old.projectPath,
            model: old.model,
            createdAt: old.createdAt,
            lastActiveAt: Date(),
            isArchived: false
        )
        sessions = updated
        saveToDisk()
    }

    /// 删除指定会话
    public func delete(id: String) {
        let updated = sessions.filter { $0.id != id }
        guard updated.count != sessions.count else { return }
        sessions = updated
        saveToDisk()
    }

    /// 批量删除所有归档会话
    /// - Returns: 实际删除的会话数量
    @discardableResult
    public func deleteAllArchived() -> Int {
        let removed = sessions.filter(\.isArchived).count
        guard removed > 0 else { return 0 }
        sessions = sessions.filter { !$0.isArchived }
        saveToDisk()
        return removed
    }

    /// 获取活跃会话，按项目路径分组，按最后活跃时间排序
    public func groupedActiveSessions() -> [(projectName: String, sessions: [ClaudeSession])] {
        let active = sessions
            .filter { !$0.isArchived }
            .sorted { $0.lastActiveAt > $1.lastActiveAt }

        var groups: [(key: String, sessions: [ClaudeSession])] = []
        var seen: [String: Int] = [:]

        for session in active {
            let name = session.projectName.isEmpty
                ? String(localized: "session.unknown_project", defaultValue: "未知项目")
                : session.projectName
            if let idx = seen[name] {
                groups[idx].sessions.append(session)
            } else {
                seen[name] = groups.count
                groups.append((key: name, sessions: [session]))
            }
        }

        return groups.map { (projectName: $0.key, sessions: $0.sessions) }
    }

    /// 获取归档会话
    public func archivedSessions() -> [ClaudeSession] {
        sessions
            .filter(\.isArchived)
            .sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    // MARK: - 持久化

    private func saveToDisk() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(sessions)
            try data.write(to: storageURL, options: .atomic)
        } catch {
            print("[SessionManager] 保存失败: \(error)")
        }
    }

    private static func loadFromDisk(url: URL) -> [ClaudeSession] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode([ClaudeSession].self, from: data)
        } catch {
            print("[SessionManager] 加载失败: \(error)")
            return []
        }
    }
}
