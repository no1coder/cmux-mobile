import SwiftUI

/// 终端列表视图，显示所有可用的终端 surface
struct TerminalListView: View {
    @EnvironmentObject var messageStore: MessageStore

    var body: some View {
        NavigationStack {
            Group {
                if messageStore.surfaces.isEmpty {
                    emptyStateView
                } else {
                    surfaceList
                }
            }
            .navigationTitle("终端")
        }
    }

    // MARK: - 子视图

    private var surfaceList: some View {
        List(messageStore.surfaces) { surface in
            NavigationLink(destination: TerminalView(surfaceID: surface.id)) {
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
