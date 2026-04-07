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
            TerminalView(surfaceID: surface.id)
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
                            SurfaceRowView(surface: surface)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
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

    // MARK: - 分组逻辑

    private struct WorkspaceGroup {
        let workspaceID: String
        let workspaceName: String
        let surfaces: [Surface]

        var displayName: String {
            if workspaceName.isEmpty {
                return "工作区"
            }
            return workspaceName
        }
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
                    }
                }

                Text(surface.ref)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontDesign(.monospaced)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
