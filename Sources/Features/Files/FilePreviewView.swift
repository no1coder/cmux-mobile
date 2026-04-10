import SwiftUI
import AVKit
import PDFKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 文件预览视图：支持图片（缩放）、代码高亮、Markdown 渲染、文本（等宽字体）、视频、PDF 和二进制文件信息
struct FilePreviewView: View {
    let fileName: String
    let filePath: String
    let connection: RelayConnection

    // MARK: - 状态

    @State private var previewState: PreviewState = .loading

    // MARK: - 预览状态枚举

    enum PreviewState {
        case loading
        case image(PlatformImage)
        case text(String)
        case code(language: String, content: String)
        case markdown(String)
        case video(URL)          // 视频播放（临时文件）
        case pdf(URL)            // PDF 渲染（临时文件）
        case binary(info: FileInfo) // 不支持预览的二进制文件信息
        case error(String)
    }

    // MARK: - 跨平台图片类型

    #if os(iOS)
    typealias PlatformImage = UIImage
    #else
    typealias PlatformImage = NSImage
    #endif

    var body: some View {
        Group {
            switch previewState {
            case .loading:
                loadingView

            case .image(let image):
                imagePreview(image: image)

            case .text(let content):
                textPreview(content: content)

            case .code(let language, let content):
                codePreview(language: language, content: content)

            case .markdown(let content):
                markdownPreview(content: content)

            case .video(let url):
                videoPreview(url: url)

            case .pdf(let url):
                pdfPreview(url: url)

            case .binary(let info):
                binaryInfoView(info: info)

            case .error(let message):
                errorView(message: message)
            }
        }
        .navigationTitle(fileName)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { loadFile() }
    }

    // MARK: - 子视图

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "files.preview.loading", defaultValue: "正在加载文件…"))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func imagePreview(image: PlatformImage) -> some View {
        #if os(iOS)
        ScrollView([.horizontal, .vertical]) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding()
        }
        #else
        ScrollView([.horizontal, .vertical]) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding()
        }
        #endif
    }

    private func textPreview(content: String) -> some View {
        ScrollView {
            Text(content)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
    }

    private func codePreview(language: String, content: String) -> some View {
        ScrollView {
            SyntaxHighlightedCodeView(
                code: content,
                language: language,
                showLineNumbers: true,
                maxLines: 0
            )
            .padding(8)
        }
    }

    private func markdownPreview(content: String) -> some View {
        ScrollView {
            MarkdownView(content: content)
                .padding()
        }
    }

    private func videoPreview(url: URL) -> some View {
        VideoPlayer(player: AVPlayer(url: url))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pdfPreview(url: URL) -> some View {
        PDFKitView(url: url)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func binaryInfoView(info: FileInfo) -> some View {
        VStack(spacing: 16) {
            Image(systemName: iconForMimeType(info.mimeType))
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(info.name)
                .font(.headline)
            Text(info.mimeType)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(formatFileSize(info.size))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(String(localized: "files.preview.no_preview", defaultValue: "此文件类型暂不支持预览"))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Button(String(localized: "files.retry", defaultValue: "重试")) {
                loadFile()
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 数据加载

    /// 发送 file.read 命令，使用回调接收响应
    private func loadFile() {
        previewState = .loading
        // C4: 使用 sendWithResponse 注册响应回调
        connection.sendWithResponse([
            "method": "file.read",
            "params": ["path": filePath]
        ]) { result in
            DispatchQueue.main.async {
                let resultDict = result["result"] as? [String: Any] ?? result
                handleResponse(resultDict)
            }
        }
    }

    /// 处理 file.read 响应：支持 base64 图片/视频/PDF 和 utf8 文本
    /// - Parameter result: JSON-RPC result 字段内容
    func handleResponse(_ result: [String: Any]) {
        let mimeType = result["mimeType"] as? String ?? ""
        let fileSize = result["size"] as? Int64 ?? 0

        // base64 编码的二进制文件
        if let encoding = result["encoding"] as? String,
           encoding == "base64",
           let content = result["content"] as? String,
           let data = Data(base64Encoded: content) {

            // 图片
            if mimeType.hasPrefix("image/") {
                #if os(iOS)
                if let image = UIImage(data: data) {
                    previewState = .image(image)
                    return
                }
                #else
                if let image = NSImage(data: data) {
                    previewState = .image(image)
                    return
                }
                #endif
                previewState = .error(String(localized: "files.preview.decode_error", defaultValue: "图片解码失败"))
                return
            }

            // 视频
            if mimeType.hasPrefix("video/") || Self.isVideoFile(fileName) {
                if let url = saveTempFile(data: data, name: fileName) {
                    previewState = .video(url)
                } else {
                    previewState = .error(String(localized: "files.preview.video_load_error", defaultValue: "视频文件加载失败"))
                }
                return
            }

            // PDF
            if mimeType.contains("pdf") || Self.isPDFFile(fileName) {
                if let url = saveTempFile(data: data, name: fileName) {
                    previewState = .pdf(url)
                } else {
                    previewState = .error(String(localized: "files.preview.pdf_load_error", defaultValue: "PDF 文件加载失败"))
                }
                return
            }

            // 其他二进制文件 — 显示文件信息
            previewState = .binary(info: FileInfo(name: fileName, mimeType: mimeType, size: fileSize))
            return
        }

        // utf8 文本文件，按文件类型路由
        if let content = result["content"] as? String {
            if Self.isMarkdownFile(fileName) {
                previewState = .markdown(content)
            } else if let lang = Self.detectLanguage(fileName) {
                previewState = .code(language: lang, content: content)
            } else {
                previewState = .text(content)
            }
            return
        }

        // 尝试从 Data 解析 utf8 文本
        if let contentData = result["content"] as? Data,
           let text = String(data: contentData, encoding: .utf8) {
            previewState = .text(text)
            return
        }

        previewState = .error(String(localized: "files.preview.unsupported", defaultValue: "不支持的文件格式"))
    }

    // MARK: - 工具方法

    /// 将数据保存到临时文件，返回 URL
    private func saveTempFile(data: Data, name: String) -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("cmux-preview-\(UUID().uuidString)-\(name)")
        do {
            try data.write(to: url)
            return url
        } catch {
            print("[files] 保存临时文件失败: \(error)")
            return nil
        }
    }

    /// 根据 MIME 类型返回对应的 SF Symbol 图标名
    private func iconForMimeType(_ mime: String) -> String {
        if mime.hasPrefix("video/") { return "film" }
        if mime.hasPrefix("audio/") { return "waveform" }
        if mime.contains("pdf") { return "doc.richtext" }
        if mime.contains("zip") || mime.contains("tar") || mime.contains("gzip") { return "doc.zipper" }
        return "doc"
    }

    /// 格式化文件大小为人类可读字符串
    private func formatFileSize(_ bytes: Int64) -> String {
        let kb = Double(bytes) / 1024
        if kb < 1 { return "\(bytes) B" }
        let mb = kb / 1024
        if mb < 1 { return String(format: "%.1f KB", kb) }
        let gb = mb / 1024
        if gb < 1 { return String(format: "%.1f MB", mb) }
        return String(format: "%.1f GB", gb)
    }

    /// 根据文件名扩展名判断是否为图片类型
    static func isImageFile(_ name: String) -> Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExts.contains(ext)
    }

    /// 视频文件检测
    static func isVideoFile(_ name: String) -> Bool {
        let videoExts: Set<String> = ["mp4", "mov", "avi", "mkv", "webm", "m4v", "flv", "wmv"]
        let ext = (name as NSString).pathExtension.lowercased()
        return videoExts.contains(ext)
    }

    /// PDF 文件检测
    static func isPDFFile(_ name: String) -> Bool {
        (name as NSString).pathExtension.lowercased() == "pdf"
    }

    /// 根据文件扩展名检测编程语言
    private static func detectLanguage(_ fileName: String) -> String? {
        let ext = (fileName as NSString).pathExtension.lowercased()
        switch ext {
        case "swift": return "swift"
        case "py": return "python"
        case "js", "jsx": return "javascript"
        case "ts", "tsx": return "typescript"
        case "go": return "go"
        case "rs": return "rust"
        case "java": return "java"
        case "c", "h": return "c"
        case "cpp", "cc", "cxx", "hpp": return "cpp"
        case "rb": return "ruby"
        case "sh", "bash", "zsh": return "bash"
        case "sql": return "sql"
        case "json": return "json"
        case "yaml", "yml": return "yaml"
        case "html", "htm": return "html"
        case "css", "scss": return "css"
        case "kt": return "kotlin"
        case "xml", "svg", "plist": return "html"
        case "toml": return "yaml"
        case "dockerfile": return "bash"
        default: return nil
        }
    }

    private static func isMarkdownFile(_ fileName: String) -> Bool {
        let ext = (fileName as NSString).pathExtension.lowercased()
        return ext == "md" || ext == "markdown"
    }
}

// MARK: - PDFKitView

#if os(iOS)
/// 使用 UIViewRepresentable 包装 PDFView 以在 SwiftUI 中渲染 PDF
struct PDFKitView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.document = PDFDocument(url: url)
        return pdfView
    }

    func updateUIView(_ uiView: PDFView, context: Context) {}
}
#endif

// MARK: - FileInfo

/// 文件基本信息，用于无法预览的二进制文件展示
struct FileInfo {
    let name: String
    let mimeType: String
    let size: Int64
}
