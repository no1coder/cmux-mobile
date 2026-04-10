import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 浏览器预览视图：展示远程浏览器截图，支持 URL 栏、前进/后退/刷新以及自动刷新
struct BrowserPreviewView: View {
    let surfaceID: String
    let connection: RelayConnection

    // MARK: - 跨平台图片类型

    #if os(iOS)
    typealias PlatformImage = UIImage
    #else
    typealias PlatformImage = NSImage
    #endif

    // MARK: - 状态

    /// 当前截图
    @State private var screenshot: PlatformImage?
    /// 当前页面 URL
    @State private var currentURL: String = ""
    /// 是否正在加载截图
    @State private var isLoading: Bool = false
    /// 错误信息
    @State private var errorMessage: String?
    /// 是否开启自动刷新（3 秒间隔）
    @State private var autoRefreshEnabled: Bool = false
    /// 自动刷新定时器任务
    @State private var autoRefreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            urlBar
            Divider()
            screenshotArea
        }
        .navigationTitle(String(localized: "browser.title", defaultValue: "浏览器"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar { toolbarContent }
        .onAppear {
            fetchURL()
            fetchScreenshot()
        }
        .onDisappear {
            stopAutoRefresh()
        }
        .onChange(of: autoRefreshEnabled) { _, enabled in
            if enabled {
                startAutoRefresh()
            } else {
                stopAutoRefresh()
            }
        }
    }

    // MARK: - URL 栏

    private var urlBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "globe")
                .foregroundStyle(.secondary)
                .font(.body)

            Text(currentURL.isEmpty
                 ? String(localized: "browser.url.placeholder", defaultValue: "正在获取 URL…")
                 : currentURL)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(currentURL.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    // MARK: - 截图区域

    private var screenshotArea: some View {
        Group {
            if isLoading && screenshot == nil {
                loadingView
            } else if let error = errorMessage, screenshot == nil {
                errorView(message: error)
            } else if let image = screenshot {
                screenshotScrollView(image: image)
            } else {
                placeholderView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(String(localized: "browser.loading", defaultValue: "正在加载截图…"))
                .foregroundStyle(.secondary)
        }
    }

    private var placeholderView: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(String(localized: "browser.no_screenshot", defaultValue: "暂无截图"))
                .foregroundStyle(.secondary)
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
            Button(String(localized: "browser.retry", defaultValue: "重试")) {
                fetchScreenshot()
            }
        }
        .padding()
    }

    private func screenshotScrollView(image: PlatformImage) -> some View {
        ScrollView([.horizontal, .vertical]) {
            #if os(iOS)
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .padding(4)
            #else
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .padding(4)
            #endif
        }
    }

    // MARK: - 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .automatic) {
            // 后退
            Button {
                sendBack()
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel(String(localized: "browser.back", defaultValue: "后退"))

            // 前进
            Button {
                sendForward()
            } label: {
                Image(systemName: "chevron.right")
            }
            .accessibilityLabel(String(localized: "browser.forward", defaultValue: "前进"))

            // 刷新
            Button {
                sendRefresh()
                fetchURL()
                fetchScreenshot()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .accessibilityLabel(String(localized: "browser.refresh", defaultValue: "刷新"))

            // 自动刷新开关
            Toggle(isOn: $autoRefreshEnabled) {
                Label(
                    String(localized: "browser.auto_refresh", defaultValue: "自动刷新"),
                    systemImage: "timer"
                )
            }
            .toggleStyle(.button)
            .tint(autoRefreshEnabled ? .green : nil)
            .accessibilityLabel(String(localized: "browser.auto_refresh", defaultValue: "自动刷新"))
        }
    }

    // MARK: - 命令发送

    /// 发送 browser.screenshot 命令，使用回调接收响应
    func fetchScreenshot() {
        isLoading = true
        errorMessage = nil
        // C4: 使用 sendWithResponse 注册响应回调
        connection.sendWithResponse([
            "method": "browser.screenshot",
            "params": ["surface_id": surfaceID]
        ]) { result in
            DispatchQueue.main.async {
                let resultDict = result["result"] as? [String: Any] ?? result
                handleScreenshotResponse(resultDict)
            }
        }
    }

    /// 发送 browser.url.get 命令，使用回调接收响应
    func fetchURL() {
        // C4: 使用 sendWithResponse 注册响应回调
        connection.sendWithResponse([
            "method": "browser.url.get",
            "params": ["surface_id": surfaceID]
        ]) { result in
            DispatchQueue.main.async {
                let resultDict = result["result"] as? [String: Any] ?? result
                handleURLResponse(resultDict)
            }
        }
    }

    /// 发送 browser.back 命令
    func sendBack() {
        connection.send([
            "method": "browser.back",
            "params": ["surface_id": surfaceID]
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            fetchURL()
            fetchScreenshot()
        }
    }

    /// 发送 browser.forward 命令
    func sendForward() {
        connection.send([
            "method": "browser.forward",
            "params": ["surface_id": surfaceID]
        ])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            fetchURL()
            fetchScreenshot()
        }
    }

    /// 发送 browser.refresh 命令
    func sendRefresh() {
        connection.send([
            "method": "browser.refresh",
            "params": ["surface_id": surfaceID]
        ])
    }

    // MARK: - 响应处理

    /// 处理 browser.screenshot 响应：base64 编码图片数据
    func handleScreenshotResponse(_ result: [String: Any]) {
        guard let content = result["content"] as? String,
              let imageData = Data(base64Encoded: content) else {
            errorMessage = String(localized: "browser.decode_error", defaultValue: "截图解码失败")
            isLoading = false
            return
        }

        #if os(iOS)
        guard let image = UIImage(data: imageData) else {
            errorMessage = String(localized: "browser.decode_error", defaultValue: "截图解码失败")
            isLoading = false
            return
        }
        #else
        guard let image = NSImage(data: imageData) else {
            errorMessage = String(localized: "browser.decode_error", defaultValue: "截图解码失败")
            isLoading = false
            return
        }
        #endif

        screenshot = image
        isLoading = false
        errorMessage = nil
    }

    /// 处理 browser.url.get 响应
    func handleURLResponse(_ result: [String: Any]) {
        if let url = result["url"] as? String {
            currentURL = url
        }
    }

    // MARK: - 自动刷新

    private func startAutoRefresh() {
        stopAutoRefresh()
        autoRefreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 秒
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    fetchURL()
                    fetchScreenshot()
                }
            }
        }
    }

    private func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }
}
