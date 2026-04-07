import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 文件预览视图：支持图片（缩放）和文本（等宽字体）两种模式
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

    /// 发送 file.read 命令
    private func loadFile() {
        previewState = .loading
        connection.send([
            "method": "file.read",
            "params": ["path": filePath]
        ])
        // 实际响应由 handleResponse 处理
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

        // 检查是否为 utf8 文本
        if let content = result["content"] as? String {
            previewState = .text(content)
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
}
