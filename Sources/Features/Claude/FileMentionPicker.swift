import SwiftUI

/// 文件条目（用于 @ 提及文件选择器）
struct MentionFileEntry: Equatable {
    let name: String
    let isDirectory: Bool
}

/// @ 文件提及选择器视图
struct FileMentionPicker: View {
    @Binding var inputText: String
    @Binding var showFilePicker: Bool
    @Binding var fileList: [MentionFileEntry]
    @Binding var isLoading: Bool
    @Binding var errorMessage: String?
    @Binding var mentionQuery: String
    @Binding var mentionBasePath: String
    let rootPath: String
    @EnvironmentObject var relayConnection: RelayConnection
    @StateObject private var requestGate = LatestOnlyRequestGate()

    /// 根据 mentionQuery 模糊过滤的文件列表
    private var filteredFileList: [MentionFileEntry] {
        guard !mentionQuery.isEmpty else { return fileList }
        let query = mentionQuery.lowercased()
        return fileList.filter { fuzzyMatch(query: query, target: $0.name.lowercased()) }
    }

    private var currentDisplayPath: String {
        guard !mentionBasePath.isEmpty else { return rootPath }
        let trimmedBasePath = mentionBasePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmedBasePath.isEmpty else { return rootPath }
        return rootPath + "/" + trimmedBasePath
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "doc.text").font(.system(size: 12)).foregroundStyle(.blue)
                Text(currentDisplayPath)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.blue.opacity(0.6))
                    .lineLimit(1)
                Spacer()
                if !mentionQuery.isEmpty {
                    Text("\(filteredFileList.count) 个结果")
                        .font(.system(size: 10))
                        .foregroundStyle(CMColors.textTertiary)
                }
                Button { dismissMentionPicker() } label: {
                    Image(systemName: "xmark").font(.system(size: 10)).foregroundStyle(CMColors.textTertiary)
                }
                .frame(width: 28, height: 28)
                .accessibilityLabel(String(localized: "chat.mention.close", defaultValue: "关闭文件选择器"))
            }.padding(.horizontal, 16).padding(.vertical, 8)

            if isLoading {
                HStack {
                    ProgressView().scaleEffect(0.6).tint(.blue)
                    Text("加载…").font(.system(size: 12)).foregroundStyle(CMColors.textTertiary)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else if let errorMessage {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(.orange)
                        Text(errorMessage)
                            .font(.system(size: 12))
                            .foregroundStyle(CMColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Button {
                        loadFileList(subpath: mentionBasePath)
                    } label: {
                        Label(String(localized: "common.retry", defaultValue: "重试"), systemImage: "arrow.clockwise")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else if fileList.isEmpty {
                HStack {
                    Image(systemName: "folder")
                        .font(.system(size: 11))
                        .foregroundStyle(CMColors.textTertiary)
                    Text("当前目录为空")
                        .font(.system(size: 12))
                        .foregroundStyle(CMColors.textTertiary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            } else if filteredFileList.isEmpty {
                HStack {
                    Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(CMColors.textTertiary)
                    Text("无匹配文件").font(.system(size: 12)).foregroundStyle(CMColors.textTertiary)
                }.padding(.horizontal, 16).padding(.vertical, 12)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(filteredFileList, id: \.name) { file in
                            Button {
                                if file.isDirectory {
                                    navigateToSubdirectory(file.name)
                                } else {
                                    selectFile(file)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: file.isDirectory ? "folder.fill" : "doc.text")
                                        .font(.system(size: 12)).foregroundStyle(file.isDirectory ? .yellow : .blue).frame(width: 16)
                                    Text(file.name).font(.system(size: 13)).foregroundStyle(CMColors.textPrimary).lineLimit(1)
                                    Spacer()
                                    if file.isDirectory {
                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 9))
                                            .foregroundStyle(CMColors.textTertiary)
                                    }
                                }.padding(.horizontal, 16).padding(.vertical, 8)
                            }
                        }
                    }
                }.frame(maxHeight: 200)
            }
        }.background(CMColors.menuBackground)
    }

    // MARK: - 文件选择操作

    /// 简单模糊匹配：查询字符按顺序出现在目标中
    private func fuzzyMatch(query: String, target: String) -> Bool {
        var targetIdx = target.startIndex
        for ch in query {
            guard let found = target[targetIdx...].firstIndex(of: ch) else { return false }
            targetIdx = target.index(after: found)
        }
        return true
    }

    /// 进入子目录
    private func navigateToSubdirectory(_ dirName: String) {
        let newBase = mentionBasePath.isEmpty ? dirName + "/" : mentionBasePath + dirName + "/"
        mentionBasePath = newBase
        mentionQuery = ""
        updateMentionInInput(newBase)
        loadFileList(subpath: newBase)
    }

    /// 选中文件，插入到输入框
    private func selectFile(_ file: MentionFileEntry) {
        let fullPath = mentionBasePath + file.name
        let textBeforeAt = extractTextBeforeLastAt(inputText)
        inputText = textBeforeAt + "@" + fullPath + " "
        dismissMentionPicker()
    }

    /// 关闭提及选择器并重置状态
    func dismissMentionPicker() {
        showFilePicker = false
        isLoading = false
        errorMessage = nil
        mentionQuery = ""
        mentionBasePath = ""
    }

    /// 更新输入框中 @ 后的文本
    private func updateMentionInInput(_ path: String) {
        let textBeforeAt = extractTextBeforeLastAt(inputText)
        inputText = textBeforeAt + "@" + path
    }

    /// 提取输入框中最后一个 @ 之前的文本
    private func extractTextBeforeLastAt(_ text: String) -> String {
        guard let atRange = text.range(of: "@", options: .backwards) else { return text }
        return String(text[text.startIndex..<atRange.lowerBound])
    }

    /// 加载文件列表
    func loadFileList(subpath: String = "") {
        let trimmedSubpath = subpath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let fullPath = trimmedSubpath.isEmpty ? rootPath : rootPath + "/" + trimmedSubpath
        let token = requestGate.begin("mention-file-list")
        isLoading = true
        errorMessage = nil
        relayConnection.sendWithResponse(["method": "file.list", "params": ["path": fullPath]]) { result in
            guard requestGate.isLatest(token, for: "mention-file-list") else { return }
            isLoading = false
            let resultDict = result["result"] as? [String: Any] ?? result
            if let entries = resultDict["entries"] as? [[String: Any]] {
                fileList = entries.compactMap {
                    guard let name = $0["name"] as? String else { return nil }
                    return MentionFileEntry(name: name, isDirectory: ($0["type"] as? String) == "directory")
                }.sorted { a, b in
                    if a.isDirectory != b.isDirectory { return a.isDirectory }
                    return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
                }
                return
            }

            let fallbackMessage: String
            if trimmedSubpath.isEmpty {
                fallbackMessage = String(localized: "chat.mention.load_failed", defaultValue: "无法加载文件列表，请稍后重试。")
            } else {
                fallbackMessage = String(localized: "chat.mention.load_failed_subpath", defaultValue: "无法加载这个目录，请稍后重试。")
            }
            fileList = []
            errorMessage = FileExplorerView.extractErrorMessage(from: result) ?? fallbackMessage
        }
    }
}
