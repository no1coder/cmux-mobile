import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 文件预览视图：支持图片（缩放）、代码高亮、Markdown 渲染和文本（等宽字体）四种模式
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

    /// 处理 file.read 响应：支持 base64 图片和 utf8 文本
    /// - Parameter result: JSON-RPC result 字段内容
    func handleResponse(_ result: [String: Any]) {
        // 检查是否为 base64 编码图片
        if let encoding = result["encoding"] as? String,
           encoding == "base64",
           let content = result["content"] as? String,
           let imageData = Data(base64Encoded: content) {
            #if os(iOS)
            if let image = UIImage(data: imageData) {
                previewState = .image(image)
                return
            }
            #else
            if let image = NSImage(data: imageData) {
                previewState = .image(image)
                return
            }
            #endif
            previewState = .error(String(localized: "files.preview.decode_error", defaultValue: "图片解码失败"))
            return
        }

        // 检查是否为 utf8 文本，并按文件类型路由
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

    /// 根据文件名扩展名判断是否为图片类型
    static func isImageFile(_ name: String) -> Bool {
        let imageExts: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff"]
        let ext = (name as NSString).pathExtension.lowercased()
        return imageExts.contains(ext)
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
