import SwiftUI

/// 终端列表视图，显示所有可用的终端 surface（包括 browser 类型跳转到 BrowserPreviewView）
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

    /// 未连接提示
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

    /// 根据 surface 类型返回对应的目标视图
    @ViewBuilder
    private func destinationView(for surface: Surface) -> some View {
        switch surface.type {
        case .browser:
            BrowserPreviewView(surfaceID: surface.id, connection: relayConnection)
        case .terminal:
            TerminalView(surfaceID: surface.id)
        }
    }

    // MARK: - 子视图

    private var surfaceList: some View {
        List(messageStore.surfaces) { surface in
            NavigationLink(destination: destinationView(for: surface)) {
                SurfaceRowView(surface: surface)
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private var emptyStateView: some View {
        Group {
            if #available(iOS 17.0, macOS 14.0, *) {
                ContentUnavailableView(
                    "没有终端",
                    systemImage: "terminal",
                    description: Text("连接到 Mac 后终端列表将显示在这里")
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("没有终端")
                        .font(.title2)
                    Text("连接到 Mac 后终端列表将显示在这里")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
        }
    }
}

// MARK: - Surface 行视图

private struct SurfaceRowView: View {
    let surface: Surface

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.green)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(surface.title)
                        .font(.body)
                        .fontWeight(.medium)

                    if surface.focused {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 6))
                            .foregroundStyle(.green)
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
