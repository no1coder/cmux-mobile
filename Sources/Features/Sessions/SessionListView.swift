import SwiftUI

/// Claude 会话列表视图，按项目分组展示，支持归档/恢复
struct SessionListView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    /// 是否展开归档区域
    @State private var showArchived = false

    var body: some View {
        let grouped = sessionManager.groupedActiveSessions()
        let archived = sessionManager.archivedSessions()

        Group {
            if grouped.isEmpty && archived.isEmpty {
                emptyStateView
            } else {
                sessionList(grouped: grouped, archived: archived)
            }
        }
    }

    // MARK: - 列表

    private func sessionList(
        grouped: [(projectName: String, sessions: [ClaudeSession])],
        archived: [ClaudeSession]
    ) -> some View {
        List {
            // 活跃会话按项目分组
            ForEach(grouped, id: \.projectName) { group in
                Section {
                    ForEach(group.sessions) { session in
                        NavigationLink {
                            TerminalDetailView(
                                surfaceID: session.surfaceID,
                                surfaceTitle: session.title
                            )
                            .environmentObject(messageStore)
                            .environmentObject(inputManager)
                            .environmentObject(relayConnection)
                        } label: {
                            SessionRowView(session: session)
                        }
                        .swipeActions(edge: .trailing) {
                            Button {
                                withAnimation {
                                    sessionManager.archive(id: session.id)
                                }
                            } label: {
                                Label(
                                    String(localized: "session.archive", defaultValue: "归档"),
                                    systemImage: "archivebox"
                                )
                            }
                            .tint(.orange)
                        }
                    }
                } header: {
                    projectSectionHeader(name: group.projectName, count: group.sessions.count)
                }
            }

            // 归档区域
            if !archived.isEmpty {
                Section {
                    if showArchived {
                        ForEach(archived) { session in
                            SessionRowView(session: session, isArchived: true)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        withAnimation {
                                            sessionManager.delete(id: session.id)
                                        }
                                    } label: {
                                        Label(
                                            String(localized: "session.delete", defaultValue: "删除"),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        withAnimation {
                                            sessionManager.restore(id: session.id)
                                        }
                                    } label: {
                                        Label(
                                            String(localized: "session.restore", defaultValue: "恢复"),
                                            systemImage: "arrow.uturn.backward"
                                        )
                                    }
                                    .tint(.green)
                                }
                        }
                    }
                } header: {
                    Button {
                        withAnimation { showArchived.toggle() }
                    } label: {
                        HStack {
                            Image(systemName: "archivebox")
                                .font(.caption)
                            Text(String(
                                localized: "session.archived_section",
                                defaultValue: "已归档 (\(archived.count))"
                            ))
                            .font(.caption)
                            .fontWeight(.medium)
                            Spacer()
                            Image(systemName: showArchived ? "chevron.up" : "chevron.down")
                                .font(.caption2)
                        }
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - 项目分组头

    private func projectSectionHeader(name: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.caption)
                .foregroundStyle(.blue)
            Text(name)
                .font(.caption)
                .fontWeight(.semibold)
            if count > 1 {
                Text("(\(count))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - 空状态

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48))
                .foregroundStyle(.purple.opacity(0.6))
            Text(String(localized: "session.empty.title", defaultValue: "没有 Claude 会话"))
                .font(.title3)
                .fontWeight(.medium)
            Text(String(
                localized: "session.empty.description",
                defaultValue: "在 Mac 终端启动 Claude Code 后，会话将自动出现在这里"
            ))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - 会话行视图

/// 单个 Claude 会话的行展示
private struct SessionRowView: View {
    let session: ClaudeSession
    var isArchived: Bool = false

    /// 相对时间格式化
    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: session.lastActiveAt, relativeTo: Date())
    }

    /// 显示标题：优先用项目路径，其次用标题
    private var displayTitle: String {
        if !session.projectPath.isEmpty {
            return session.projectPath
        }
        return session.title.isEmpty
            ? String(localized: "session.untitled", defaultValue: "未命名会话")
            : session.title
    }

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            ZStack {
                Circle()
                    .fill(isArchived ? Color.gray.opacity(0.15) : Color.purple.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(isArchived ? .gray : .purple)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(displayTitle)
                    .font(.body)
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .opacity(isArchived ? 0.6 : 1.0)

                HStack(spacing: 8) {
                    // 模型标签
                    if !session.model.isEmpty {
                        Text(session.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    // 时间
                    Text(relativeTime)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if isArchived {
                Image(systemName: "archivebox")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
