import Testing
import Foundation
#if canImport(cmux_mobile)
@testable import cmux_mobile
#elseif canImport(cmux_core)
@testable import cmux_core
import cmux_models
#endif

@Suite("SessionManager Tests")
@MainActor
struct SessionManagerTests {

    // MARK: - 辅助方法

    private func makeManager() -> SessionManager {
        let url = sessionStorageURL()
        try? FileManager.default.removeItem(at: url)
        return SessionManager()
    }

    private func sessionStorageURL() -> URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return dir.appendingPathComponent("claude-sessions.json")
    }

    private func makeSurface(
        id: String = "surf-001",
        title: String = "Claude Code — ~/project",
        focused: Bool = false
    ) -> Surface {
        Surface(
            id: id,
            ref: "ref-\(id)",
            index: 0,
            type: .terminal,
            title: title,
            focused: focused
        )
    }

    // MARK: - syncFromSurfaces 测试

    @Test("从 Surface 列表创建会话")
    func syncCreatesSession() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/my-project")
        manager.syncFromSurfaces([surface])

        #expect(manager.sessions.count == 1)
        #expect(manager.sessions.first?.surfaceID == "s1")
    }

    @Test("非 Claude 标题的 Surface 不创建会话")
    func syncIgnoresNonClaude() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Terminal — bash")
        manager.syncFromSurfaces([surface])

        #expect(manager.sessions.isEmpty)
    }

    @Test("重复 sync 不创建重复会话")
    func syncDeduplicates() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")

        manager.syncFromSurfaces([surface])
        manager.syncFromSurfaces([surface])

        // 同一 surfaceID 不应重复创建
        let matchingSessions = manager.sessions.filter { $0.surfaceID == "s1" }
        #expect(matchingSessions.count == 1)
    }

    @Test("surface 列表刷新不会伪造最近活跃时间")
    func syncPreservesLastActiveAt() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let baseDate = manager.sessions.first!.lastActiveAt
        let originalDate = baseDate.addingTimeInterval(60)
        manager.touchActivity(surfaceID: "s1", at: originalDate)
        manager.syncFromSurfaces([surface])

        let session = manager.sessions.first { $0.surfaceID == "s1" }
        #expect(session?.lastActiveAt == originalDate)
    }

    @Test("markAsClaudeSession 只修正元数据，不刷新最近活跃时间")
    func markAsClaudeSessionPreservesLastActiveAt() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let baseDate = manager.sessions.first!.lastActiveAt
        let originalDate = baseDate.addingTimeInterval(60)
        manager.touchActivity(surfaceID: "s1", at: originalDate)
        manager.markAsClaudeSession(surfaceID: "s1", title: "Fix build issue", cwd: "~/project")

        let session = manager.sessions.first { $0.surfaceID == "s1" }
        #expect(session?.lastActiveAt == originalDate)
        #expect(session?.title == "Fix build issue")
    }

    @Test("touchActivity 只在真实活动时刷新最近活跃时间")
    func touchActivityUpdatesLastActiveAt() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let baseDate = manager.sessions.first!.lastActiveAt
        let originalDate = baseDate.addingTimeInterval(60)
        let newerDate = baseDate.addingTimeInterval(123)
        manager.touchActivity(surfaceID: "s1", at: originalDate)
        manager.touchActivity(surfaceID: "s1", at: newerDate)

        let session = manager.sessions.first { $0.surfaceID == "s1" }
        #expect(session?.lastActiveAt == newerDate)
    }

    // MARK: - archive / restore / delete 测试

    @Test("归档会话")
    func archiveSession() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let sessionID = manager.sessions.first!.id
        manager.archive(id: sessionID)

        #expect(manager.archivedSessions().count == 1)
    }

    @Test("恢复归档会话")
    func restoreSession() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let sessionID = manager.sessions.first!.id
        manager.archive(id: sessionID)
        #expect(manager.archivedSessions().count == 1)

        manager.restore(id: sessionID)
        #expect(manager.archivedSessions().isEmpty)
    }

    @Test("删除会话")
    func deleteSession() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        let sessionID = manager.sessions.first!.id
        manager.delete(id: sessionID)

        #expect(manager.sessions.isEmpty)
    }

    @Test("删除不存在的 ID 无副作用")
    func deleteNonExistentID() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        manager.delete(id: "non-existent-id")
        #expect(manager.sessions.count == 1)
    }

    // MARK: - updateModel 测试

    @Test("更新模型名称")
    func updateModel() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        manager.updateModel(surfaceID: "s1", model: "Opus (1M)")

        let session = manager.sessions.first { $0.surfaceID == "s1" }
        #expect(session?.model == "Opus (1M)")
    }

    @Test("空模型名称不更新")
    func updateModelEmptyNoOp() {
        let manager = makeManager()
        let surface = makeSurface(id: "s1", title: "Claude Code — ~/project")
        manager.syncFromSurfaces([surface])

        manager.updateModel(surfaceID: "s1", model: "Sonnet")
        manager.updateModel(surfaceID: "s1", model: "")

        let session = manager.sessions.first { $0.surfaceID == "s1" }
        #expect(session?.model == "Sonnet")
    }

    // MARK: - 分组测试

    @Test("按项目名分组")
    func groupedSessions() {
        let manager = makeManager()
        manager.syncFromSurfaces([
            makeSurface(id: "s1", title: "Claude Code — ~/project-a"),
            makeSurface(id: "s2", title: "Claude Code — ~/project-a"),
            makeSurface(id: "s3", title: "Claude Code — ~/project-b"),
        ])

        let grouped = manager.groupedActiveSessions()
        #expect(grouped.count >= 1)
    }
}
