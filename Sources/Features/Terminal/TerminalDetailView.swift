import SwiftUI

/// 终端详情页 — 统一入口，支持终端模式和聊天模式切换
struct TerminalDetailView: View {
    let surfaceID: String
    let surfaceTitle: String
    @EnvironmentObject var messageStore: MessageStore
    @EnvironmentObject var inputManager: InputManager
    @EnvironmentObject var relayConnection: RelayConnection

    /// 当前显示模式
    @State private var displayMode: DisplayMode = .terminal
    /// 是否检测到 Claude Code
    @State private var isClaudeDetected = false

    enum DisplayMode: String {
        case terminal
        case chat
    }

    var body: some View {
        VStack(spacing: 0) {
            // 模式切换栏（仅 Claude 检测到时显示）
            if isClaudeDetected {
                modeSwitcher
            }

            // 内容区域
            switch displayMode {
            case .terminal:
                TerminalView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
                    .environmentObject(relayConnection)
            case .chat:
                ClaudeChatView(surfaceID: surfaceID)
                    .environmentObject(messageStore)
                    .environmentObject(inputManager)
                    .environmentObject(relayConnection)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .onAppear {
            detectClaudeMode()
        }
    }

    // MARK: - 模式切换栏

    private var modeSwitcher: some View {
        HStack(spacing: 0) {
            modeTab("终端", mode: .terminal, icon: "terminal")
            modeTab("聊天", mode: .chat, icon: "bubble.left.and.bubble.right")
        }
        .background(Color(white: 0.1))
    }

    private func modeTab(_ label: String, mode: DisplayMode, icon: String) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                displayMode = mode
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12))
                Text(label)
                    .font(.system(size: 13, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(displayMode == mode ? Color.purple.opacity(0.2) : Color.clear)
            .foregroundStyle(displayMode == mode ? .purple : .white.opacity(0.5))
        }
    }

    // MARK: - Claude 检测

    /// 读取终端内容检测是否运行 Claude Code
    private func detectClaudeMode() {
        relayConnection.sendWithResponse([
            "method": "read_screen",
            "params": ["surface_id": surfaceID],
        ]) { result in
            let resultDict = result["result"] as? [String: Any] ?? result
            if let lines = resultDict["lines"] as? [String] {
                let detected = ClaudeOutputParser.isClaudeSession(lines)
                withAnimation {
                    isClaudeDetected = detected
                    if detected {
                        displayMode = .chat
                    }
                }
            }
        }
    }
}
