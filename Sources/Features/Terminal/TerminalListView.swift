import SwiftUI

/// 终端列表视图，按 workspace 分组显示所有终端 surface
struct TerminalListView: View {
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var relayConnection: RelayConnection

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

        /// 显示名称：优先使用 workspaceName，其次使用第一个 surface 的标题，最后回退到默认名
        var displayName: String {
            if !workspaceName.isEmpty {
                return workspaceName
            }
            // 使用第一个 surface 的标题作为分组名（通常是目录路径）
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

    /// 副标题：显示类型和引用标识
    private var surfaceSubtitle: String {
        let typeLabel = surface.type == .browser
            ? String(localized: "terminal.type.browser", defaultValue: "浏览器")
            : String(localized: "terminal.type.terminal", defaultValue: "终端")
        return "\(typeLabel) - \(surface.ref)"
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
                    Text(surface.title)
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

                // 类型描述副标题
                Text(surfaceSubtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
        .background(
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.08)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}
