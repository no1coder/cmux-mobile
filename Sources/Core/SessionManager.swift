import Foundation

/// 管理 Claude Code 会话的持久化和同步
/// 使用 JSON 文件存储，避免 SwiftData 的 iOS 版本依赖
@MainActor
final class SessionManager: ObservableObject {

    /// 所有会话（活跃 + 归档）
    @Published private(set) var sessions: [ClaudeSession] = []

    /// JSON 存储路径
    private let storageURL: URL

    init() {
        let documentsDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        storageURL = documentsDir.appendingPathComponent("claude-sessions.json")
        sessions = Self.loadFromDisk(url: storageURL)
    }

    // MARK: - 公开接口

    /// 从当前 surface 列表同步会话数据
    /// 检测标题包含 "Claude Code" 的 surface，自动创建/更新会话
    func syncFromSurfaces(_ surfaces: [Surface]) {
        var updated = sessions
        var changed = false

        for surface in surfaces where surface.title.contains("Claude Code") {
            let projectPath = surface.cwd ?? surface.workspaceName ?? ""
            let sessionID = "session-\(surface.id)"

            if let index = updated.firstIndex(where: { $0.surfaceID == surface.id }) {
                // 更新已有会话的活跃时间和元数据
                let session = updated[index]
                let newSession = ClaudeSession(
                    id: session.id,
                    surfaceID: session.surfaceID,
                    title: surface.title,
                    projectPath: projectPath.isEmpty ? session.projectPath : projectPath,
                    model: session.model,
                    createdAt: session.createdAt,
                    lastActiveAt: Date(),
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

        // 标记不再活跃的会话（surface 已消失且标题不含 Claude Code）
        let activeSurfaceIDs = Set(surfaces.filter { $0.title.contains("Claude Code") }.map(\.id))
        for index in updated.indices {
            if !updated[index].isArchived && !activeSurfaceIDs.contains(updated[index].surfaceID) {
                // surface 消失但不立即归档，仅更新状态
                // 用户可手动归档
            }
        }

        if changed {
            sessions = updated
            saveToDisk()
        }
    }

    /// 更新会话的模型信息（从 ClaudeChatView 的 session info 回传）
    func updateModel(surfaceID: String, model: String) {
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
    func archive(id: String) {
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
    func restore(id: String) {
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
    func delete(id: String) {
        let updated = sessions.filter { $0.id != id }
        guard updated.count != sessions.count else { return }
        sessions = updated
        saveToDisk()
    }

    /// 获取活跃会话，按项目路径分组，按最后活跃时间排序
    func groupedActiveSessions() -> [(projectName: String, sessions: [ClaudeSession])] {
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
    func archivedSessions() -> [ClaudeSession] {
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
