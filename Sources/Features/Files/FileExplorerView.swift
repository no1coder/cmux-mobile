import SwiftUI

// MARK: - 数据模型

/// 文件条目：目录列表项
struct FileEntry: Identifiable, Codable {
    let name: String
    let type: FileEntryType
    let size: Int64?
    /// 修改时间（毫秒时间戳）
    let modified: Int64?

    /// Identifiable 所需的 id，使用 name 作为唯一标识
    var id: String { name }

    /// 格式化文件大小（目录返回空字符串）
    var formattedSize: String {
        guard let bytes = size, type == .file else { return "" }
        let kb = Double(bytes) / 1024
        if kb < 1 { return "\(bytes) B" }
        let mb = kb / 1024
        if mb < 1 { return String(format: "%.1f KB", kb) }
        let gb = mb / 1024
        if gb < 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", gb)
    }

    /// 格式化修改时间
    var formattedDate: String {
        guard let ms = modified else { return "" }
        let date = Date(timeIntervalSince1970: Double(ms) / 1000)
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    enum FileEntryType: String, Codable {
        case file
        case directory
    }

    enum CodingKeys: String, CodingKey {
        case name, type, size, modified
    }
}

// MARK: - FileExplorerView

/// 文件浏览器：展示远程文件系统目录，支持进入子目录和预览文件
struct FileExplorerView: View {
    @EnvironmentObject var relayConnection: RelayConnection

    /// 当前浏览的路径（相对于根目录）
    @State private var currentPath: [String] = []
    /// 当前目录中的文件条目列表
    @State private var entries: [FileEntry] = []
    /// 是否正在加载
    @State private var isLoading: Bool = false
    /// 错误信息
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Group {
                if relayConnection.status != .connected {
                    notConnectedView
                } else if currentPath.isEmpty {
                    // 根目录：显示允许访问的文件夹快捷入口
                    allowedRootsView
                } else if isLoading {
                    ProgressView(String(localized: "files.loading", defaultValue: "加载中…"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = errorMessage {
                    errorView(message: error)
                } else if entries.isEmpty {
                    emptyView
                } else {
                    fileList
                }
            }
            .navigationTitle(currentPath.isEmpty
                ? String(localized: "files.root_title", defaultValue: "文件")
                : (currentPath.last ?? "")
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .onAppear {
                if relayConnection.status == .connected && !currentPath.isEmpty {
                    loadDirectory()
                }
            }
            .onChange(of: relayConnection.status) { _, newStatus in
                if newStatus == .connected && !currentPath.isEmpty {
                    loadDirectory()
                }
            }
        }
    }

    /// 未连接提示视图
    private var notConnectedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(String(localized: "files.not_connected_title", defaultValue: "未连接到设备"))
                .font(.title3)
                .fontWeight(.medium)
            Text(String(localized: "files.not_connected_desc", defaultValue: "请先在设置中扫码配对 Mac，连接成功后即可浏览文件"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 允许的根目录

    /// Mac 端沙箱允许的工作目录
    private static let allowedRoots: [(name: String, path: String, icon: String)] = [
        ("code", "~/code", "folder.fill"),
        ("projects", "~/projects", "folder.fill"),
        ("Developer", "~/Developer", "hammer.fill"),
        ("Documents", "~/Documents", "doc.fill"),
        ("Desktop", "~/Desktop", "menubar.dock.rectangle"),
    ]

    private var allowedRootsView: some View {
        List {
            Section {
                ForEach(Self.allowedRoots, id: \.name) { root in
                    NavigationLink {
                        _ChildFileExplorerView(
                            parentPath: root.path.components(separatedBy: "/"),
                            connection: relayConnection
                        )
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(root.name)
                                    .font(.body)
                                    .fontWeight(.medium)
                                Text("~/" + root.name)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: root.icon)
                                .foregroundStyle(.blue)
                        }
                    }
                }
            } header: {
                Text(String(localized: "files.allowed_dirs", defaultValue: "可访问的目录"))
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    // MARK: - 子视图

    private var fileList: some View {
        List(entries) { entry in
            if entry.type == .directory {
                // 目录：NavigationLink 进入子目录
                NavigationLink(destination: childExplorer(entry: entry)) {
                    FileEntryRow(entry: entry)
                }
            } else {
                // 文件：NavigationLink 进入预览
                NavigationLink(
                    destination: FilePreviewView(
                        fileName: entry.name,
                        filePath: pathString(appending: entry.name),
                        connection: relayConnection
                    )
                ) {
                    FileEntryRow(entry: entry)
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    private var emptyView: some View {
        Group {
            if #available(iOS 17.0, macOS 14.0, *) {
                ContentUnavailableView(
                    String(localized: "files.empty_title", defaultValue: "目录为空"),
                    systemImage: "folder",
                    description: Text(String(localized: "files.empty_desc", defaultValue: "此目录没有任何文件"))
                )
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "folder")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "files.empty_title", defaultValue: "目录为空"))
                        .font(.title2)
                }
                .padding()
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "files.retry", defaultValue: "重试")) {
                loadDirectory()
            }
        }
        .padding()
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 返回上级目录按钮（仅在子目录时显示）
        if !currentPath.isEmpty {
            ToolbarItem(placement: .automatic) {
                Button {
                    currentPath.removeLast()
                    loadDirectory()
                } label: {
                    Label(
                        String(localized: "files.back", defaultValue: "返回"),
                        systemImage: "chevron.left"
                    )
                }
            }
        }
        // 刷新按钮
        ToolbarItem(placement: .automatic) {
            Button {
                loadDirectory()
            } label: {
                Label(
                    String(localized: "files.refresh", defaultValue: "刷新"),
                    systemImage: "arrow.clockwise"
                )
            }
        }
    }

    // MARK: - 构建子目录浏览器

    private func childExplorer(entry: FileEntry) -> some View {
        // 通过构造新的 FileExplorerView 但直接注入子路径来实现深度浏览
        _ChildFileExplorerView(
            parentPath: currentPath + [entry.name],
            connection: relayConnection
        )
    }

    // MARK: - 数据加载

    /// 发送 file.list 命令加载当前目录，使用回调接收响应
    func loadDirectory() {
        isLoading = true
        errorMessage = nil

        let path = pathString()
        // C4: 使用 sendWithResponse 注册响应回调，避免响应丢失
        relayConnection.sendWithResponse([
            "method": "file.list",
            "params": ["path": path]
        ]) { result in
            DispatchQueue.main.async { [self] in
                print("[files] file.list 响应 keys=\(result.keys.sorted())")
                // 检查是否有错误（支持多种错误格式）
                if let error = result["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    isLoading = false
                    errorMessage = message
                    return
                }
                if let error = result["error"] as? String {
                    isLoading = false
                    errorMessage = error
                    return
                }
                // 从响应中解析 entries（尝试多层嵌套）
                // 格式可能是: {"result": {"entries": [...]}}
                //          或: {"entries": [...]}
                //          或: {"result": {"result": {"entries": [...]}}}
                let entries: [[String: Any]]? = {
                    // 直接在顶层
                    if let e = result["entries"] as? [[String: Any]] { return e }
                    // 在 result 字段下
                    if let r = result["result"] as? [String: Any] {
                        if let e = r["entries"] as? [[String: Any]] { return e }
                        // 再嵌套一层
                        if let r2 = r["result"] as? [String: Any],
                           let e = r2["entries"] as? [[String: Any]] { return e }
                    }
                    return nil
                }()
                if let entries {
                    handleResponse(entries)
                } else {
                    isLoading = false
                    print("[files] 无法解析 entries, result=\(result)")
                    errorMessage = String(localized: "files.error.empty_response", defaultValue: "响应数据格式错误")
                }
            }
        }
    }

    /// 处理来自连接的 file.list 响应
    /// - Parameter result: JSON-RPC result 字段内容
    func handleResponse(_ result: [[String: Any]]) {
        let decoder = JSONDecoder()
        let mapped: [FileEntry] = result.compactMap { dict in
            guard let data = try? JSONSerialization.data(withJSONObject: dict),
                  let entry = try? decoder.decode(FileEntry.self, from: data) else {
                return nil
            }
            return entry
        }
        entries = mapped
        isLoading = false
        errorMessage = nil
    }

    // MARK: - 工具方法

    /// 将 currentPath 拼接为字符串路径（以 / 分隔）
    private func pathString(appending extra: String? = nil) -> String {
        var parts = currentPath
        if let extra { parts.append(extra) }
        let joined = parts.joined(separator: "/")
        return joined.hasPrefix("~") ? joined : "/" + joined
    }

    /// 根据文件扩展名返回对应的 SF Symbol 名称
    static func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "png", "jpg", "jpeg", "gif", "webp", "heic":
            return "photo"
        case "mp4", "mov", "avi", "mkv":
            return "video"
        case "mp3", "aac", "wav", "flac":
            return "music.note"
        case "pdf":
            return "doc.richtext"
        case "zip", "tar", "gz", "rar", "7z":
            return "archivebox"
        case "swift", "py", "js", "ts", "rb", "go", "rs", "c", "cpp", "h":
            return "chevron.left.forwardslash.chevron.right"
        case "json", "yaml", "yml", "toml", "plist", "xml":
            return "doc.badge.gearshape"
        case "md", "txt", "log":
            return "doc.text"
        default:
            return "doc"
        }
    }
}

// MARK: - 文件条目行

private struct FileEntryRow: View {
    let entry: FileEntry

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: entry.type == .directory
                  ? "folder.fill"
                  : FileExplorerView.iconForFile(entry.name))
                .foregroundStyle(entry.type == .directory ? .yellow : .blue)
                .font(.title3)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.body)

                if !entry.formattedSize.isEmpty {
                    Text(entry.formattedSize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 子目录浏览器（内部辅助视图，保持路径状态）

private struct _ChildFileExplorerView: View {
    let parentPath: [String]
    let connection: RelayConnection

    @State private var entries: [FileEntry] = []
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?
    @State private var currentPath: [String]

    init(parentPath: [String], connection: RelayConnection) {
        self.parentPath = parentPath
        self.connection = connection
        _currentPath = State(initialValue: parentPath)
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView(String(localized: "files.loading", defaultValue: "加载中…"))
            } else if let error = errorMessage {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.orange)
                    Text(error)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    Button(String(localized: "files.retry", defaultValue: "重试")) {
                        loadDirectory()
                    }
                }
                .padding()
            } else if entries.isEmpty {
                Text(String(localized: "files.empty_title", defaultValue: "目录为空"))
                    .foregroundStyle(.secondary)
            } else {
                List(entries) { entry in
                    if entry.type == .directory {
                        NavigationLink(
                            destination: _ChildFileExplorerView(
                                parentPath: currentPath + [entry.name],
                                connection: connection
                            )
                        ) {
                            HStack {
                                Image(systemName: "folder.fill").foregroundStyle(.yellow)
                                Text(entry.name)
                            }
                        }
                    } else {
                        NavigationLink(
                            destination: FilePreviewView(
                                fileName: entry.name,
                                filePath: {
                                    let joined = (currentPath + [entry.name]).joined(separator: "/")
                                    return joined.hasPrefix("~") ? joined : "/" + joined
                                }(),
                                connection: connection
                            )
                        ) {
                            HStack {
                                Image(systemName: FileExplorerView.iconForFile(entry.name))
                                    .foregroundStyle(.blue)
                                Text(entry.name)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(currentPath.last ?? "")
        .task { loadDirectory() }
    }

    private func loadDirectory() {
        isLoading = true
        errorMessage = nil
        // 构建路径：~ 开头不加 /，其他加 /
        let joined = currentPath.joined(separator: "/")
        let path = joined.hasPrefix("~") ? joined : "/" + joined
        print("[files] loadDirectory path=\(path) currentPath=\(currentPath)")
        // C4: 使用 sendWithResponse 注册响应回调
        connection.sendWithResponse([
            "method": "file.list",
            "params": ["path": path]
        ]) { result in
            DispatchQueue.main.async {
                // 检查错误（支持多种格式）
                if let error = result["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                    isLoading = false
                    return
                }
                if let error = result["error"] as? String {
                    errorMessage = error
                    isLoading = false
                    return
                }
                // 解析 entries（尝试多层嵌套）
                let rawEntries: [[String: Any]]? = {
                    if let e = result["entries"] as? [[String: Any]] { return e }
                    if let r = result["result"] as? [String: Any] {
                        if let e = r["entries"] as? [[String: Any]] { return e }
                        if let r2 = r["result"] as? [String: Any],
                           let e = r2["entries"] as? [[String: Any]] { return e }
                    }
                    return nil
                }()
                guard let rawEntries else {
                    print("[files] 子目录无法解析 entries, result=\(result)")
                    errorMessage = String(localized: "files.error.empty_response", defaultValue: "响应数据格式错误")
                    isLoading = false
                    return
                }
                let decoder = JSONDecoder()
                entries = rawEntries.compactMap { dict in
                    guard let data = try? JSONSerialization.data(withJSONObject: dict),
                          let entry = try? decoder.decode(FileEntry.self, from: data) else {
                        return nil
                    }
                    return entry
                }
                isLoading = false
            }
        }
    }
}
