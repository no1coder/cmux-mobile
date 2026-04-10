import SwiftUI

/// 终端列表视图，按 workspace 分组显示所有终端 surface
struct TerminalListView: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection
    @EnvironmentObject var sessionManager: SessionManager

    var body: some View {
        NavigationStack {
            Group {
                if relayConnection.status != .connected {
                    notConnectedView
                } else if messageStore.surfaces.isEmpty {
                    emptyStateView
                } else {
                    surfaceList
                }
            }
            .navigationTitle("终端")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        createWorkspace()
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }

    // MARK: - 未连接

    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "terminal.not_connected", defaultValue: "未连接到设备"))
                .font(.title3)
                .fontWeight(.medium)
            Text(String(localized: "terminal.not_connected_desc", defaultValue: "请先在设置中扫码配对 Mac"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 路由

    @ViewBuilder
    private func destinationView(for surface: Surface) -> some View {
        switch surface.type {
        case .browser:
            BrowserPreviewView(surfaceID: surface.id, connection: relayConnection)
        case .terminal:
            TerminalDetailView(surfaceID: surface.id, surfaceTitle: surface.title)
        }
    }

    // MARK: - 列表

    private var surfaceList: some View {
        List {
            // Claude 会话快捷入口
            let claudeGroups = sessionManager.groupedActiveSessions()
            if !claudeGroups.isEmpty {
                claudeSessionsSection(groups: claudeGroups)
            }

            // 按 workspace 分组
            let groups = groupedSurfaces()
            ForEach(groups, id: \.workspaceID) { group in
                Section(header: workspaceHeader(group)) {
                    ForEach(group.surfaces) { surface in
                        NavigationLink(destination: destinationView(for: surface)) {
                            SurfaceRowView(
                                surface: surface,
                                previewLine: lastOutputLine(for: surface.id)
                            )
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            relayConnection.requestSurfaceList()
        }
        .onChange(of: messageStore.surfaces) { _, newSurfaces in
            sessionManager.syncFromSurfaces(newSurfaces)
        }
    }

    // MARK: - Claude 会话快捷区域

    @ViewBuilder
    private func claudeSessionsSection(
        groups: [(projectName: String, sessions: [ClaudeSession])]
    ) -> some View {
        Section {
            ForEach(groups, id: \.projectName) { group in
                ForEach(group.sessions) { session in
                    NavigationLink {
                        TerminalDetailView(
                            surfaceID: session.surfaceID,
                            surfaceTitle: session.title
                        )
                    } label: {
                        claudeSessionRow(session: session)
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
            }
        } header: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.purple)
                Text(String(localized: "terminal.claude_sessions", defaultValue: "Claude 会话"))
                    .font(.caption)
                    .fontWeight(.semibold)
            }
        }
    }

    /// Claude 会话行视图
    private func claudeSessionRow(session: ClaudeSession) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color.purple.opacity(0.15))
                    .frame(width: 32, height: 32)
                Image(systemName: "sparkles")
                    .font(.system(size: 13))
                    .foregroundStyle(.purple)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(session.projectName.isEmpty
                    ? String(localized: "session.untitled", defaultValue: "未命名会话")
                    : session.projectName
                )
                .font(.body)
                .fontWeight(.medium)
                .lineLimit(1)

                HStack(spacing: 6) {
                    if !session.model.isEmpty {
                        Text(session.model)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    let formatter = RelativeDateTimeFormatter()
                    Text({
                        formatter.unitsStyle = .short
                        return formatter.localizedString(for: session.lastActiveAt, relativeTo: Date())
                    }())
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    /// workspace 分组头部
    private func workspaceHeader(_ group: WorkspaceGroup) -> some View {
        HStack {
            Image(systemName: "rectangle.stack")
                .font(.caption)
            Text(group.displayName)
                .font(.caption)
                .fontWeight(.medium)
        }
    }

    private var emptyStateView: some View {
        ContentUnavailableView(
            "没有终端",
            systemImage: "terminal",
            description: Text("连接到 Mac 后终端列表将显示在这里")
        )
    }

    // MARK: - 新建 workspace

    /// 发送 workspace.create 命令到 Mac
    private func createWorkspace() {
        relayConnection.sendWithResponse([
            "method": "workspace.create",
        ]) { _ in
            // 创建成功后刷新 surface 列表
            relayConnection.requestSurfaceList()
        }
    }

    // MARK: - 分组逻辑

    private struct WorkspaceGroup {
        let workspaceID: String
        let workspaceName: String
        let surfaces: [Surface]

        /// 显示名称：优先用 workspaceName（现在是 cwd），其次用 surface 的 cwd，最后回退
        var displayName: String {
            if !workspaceName.isEmpty {
                return workspaceName
            }
            // 优先使用 surface 的 cwd（不受进程标题覆盖影响）
            if let cwd = surfaces.first(where: { $0.cwd != nil && !$0.cwd!.isEmpty })?.cwd {
                return cwd
            }
            // 优先使用路径类标题
            if let pathTitle = surfaces.first(where: { $0.title.hasPrefix("~") || $0.title.hasPrefix("/") })?.title {
                return pathTitle
            }
            if let firstTitle = surfaces.first?.title, !firstTitle.isEmpty {
                return firstTitle
            }
            return String(localized: "terminal.default_workspace", defaultValue: "工作区")
        }
    }

    /// 获取终端快照中最后一行非空输出
    private func lastOutputLine(for surfaceID: String) -> String? {
        guard let snapshot = messageStore.snapshots[surfaceID] else { return nil }
        return snapshot.lines.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
    }

    private func groupedSurfaces() -> [WorkspaceGroup] {
        var dict: [String: (name: String, surfaces: [Surface])] = [:]
        for surface in messageStore.surfaces {
            let wsID = surface.workspaceID ?? "default"
            let wsName = surface.workspaceName ?? ""
            if dict[wsID] != nil {
                dict[wsID]?.surfaces.append(surface)
            } else {
                dict[wsID] = (name: wsName, surfaces: [surface])
            }
        }
        return dict.map { WorkspaceGroup(workspaceID: $0.key, workspaceName: $0.value.name, surfaces: $0.value.surfaces) }
            .sorted { $0.workspaceID < $1.workspaceID }
    }
}

// MARK: - Surface 行视图

private struct SurfaceRowView: View {
    let surface: Surface
    /// 终端快照预览行（最后一行输出）
    var previewLine: String?

    /// 聚焦指示灯脉冲动画
    @State private var isPulsing = false

    /// 是否为 Claude Code 会话（标题包含 Claude Code）
    private var isClaudeSession: Bool {
        surface.title.contains("Claude Code")
    }

    /// 行标题：优先用 cwd（真实目录），Claude Code 运行时标题会被覆盖
    private var displayTitle: String {
        // 优先使用 cwd（不受 Claude Code 等进程标题覆盖影响）
        if let cwd = surface.cwd, !cwd.isEmpty {
            return cwd
        }
        return surface.title.isEmpty ? "终端" : surface.title
    }

    /// 从 workspaceName 中提取 git 分支名（如果包含分支信息）
    private var gitBranch: String? {
        guard let wsName = surface.workspaceName, !wsName.isEmpty else { return nil }
        // workspaceName 可能是路径或包含分支信息
        // 常见格式：项目路径中最后一段可能是分支名
        // 如果 workspaceName 看起来像 git 分支名（不含 / 开头且非绝对路径）
        if !wsName.hasPrefix("/") && !wsName.hasPrefix("~") {
            return wsName
        }
        return nil
    }

    /// 副标题：仅显示 surface 类型
    private var surfaceSubtitle: String {
        surface.type == .browser
            ? String(localized: "terminal.type.browser", defaultValue: "浏览器")
            : String(localized: "terminal.type.terminal", defaultValue: "终端")
    }

    var body: some View {
        HStack(spacing: 12) {
            // 图标
            Image(systemName: surface.type == .browser ? "globe" : "terminal.fill")
                .foregroundStyle(surface.type == .browser ? .blue : .green)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    // Claude Code 会话标记
                    if isClaudeSession {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11))
                            .foregroundStyle(.purple)
                    }
                    Text(displayTitle)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if surface.focused {
                        Circle()
                            .fill(.green)
                            .frame(width: 6, height: 6)
                            .scaleEffect(isPulsing ? 1.4 : 1.0)
                            .opacity(isPulsing ? 0.6 : 1.0)
                            .animation(
                                .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                                value: isPulsing
                            )
                            .onAppear { isPulsing = true }
                    }
                }

                HStack(spacing: 6) {
                    // 类型描述副标题
                    Text(surfaceSubtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Git 分支标签（从 workspaceName 提取）
                    if let branch = gitBranch {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.system(size: 9))
                            Text(branch)
                                .font(.system(size: 10, design: .monospaced))
                        }
                        .foregroundStyle(.orange.opacity(0.7))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.1))
                        .clipShape(Capsule())
                    }
                }

                // 终端预览行（最后一行输出）
                if let preview = previewLine, !preview.isEmpty {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 12)
        .background(CMColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
