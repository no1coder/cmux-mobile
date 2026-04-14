// swift-tools-version: 5.9
import PackageDescription

// 注意：iOS 相关 target (cmux-mobile, cmux-mobile-app) 通过 Xcode / project.yml 构建。
// Package.swift 用于 macOS 上 `swift test` 运行纯模型测试与基础核心逻辑测试。
let package = Package(
    name: "cmux-mobile",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        // 纯模型 target（无 UIKit 依赖，macOS swift test 可用）
        .target(
            name: "cmux-models",
            dependencies: [],
            path: "Sources/Models"
        ),
        // 基础核心逻辑 target（无 SwiftUI/UIKit 依赖），供 macOS swift test 使用
        .target(
            name: "cmux-core",
            dependencies: ["cmux-models"],
            path: "Sources",
            exclude: [
                "Components",
                "Models",
                "Resources",
                "Core/ActivityStore.swift",
                "Core/AppDelegate.swift",
                "Core/AppFeatureFlags.swift",
                "Core/ComposedMessageSender.swift",
                "Core/FontLoader.swift",
                "Core/ImageCompressor.swift",
                "Core/LiveActivityManager.swift",
                "Core/MessageStore.swift",
                "Core/PushNotificationManager.swift",
                "Features/Agent/AgentDashboard.swift",
                "Features/Agent/ApprovalRequestView.swift",
                "Features/Browser",
                "Features/Claude",
                "Features/Files",
                "Features/Sessions",
                "Features/Settings",
                "Features/Terminal",
            ],
            sources: [
                "Core/ConnectionStatus.swift",
                "Core/ClaudeHistoryPagingState.swift",
                "Core/DeviceStore.swift",
                "Core/DisconnectRecovery.swift",
                "Core/E2ECryptoManager.swift",
                "Core/InputManager.swift",
                "Core/KeychainHelper.swift",
                "Core/LatestOnlyRequestGate.swift",
                "Core/OfflineMessageQueue.swift",
                "Core/PairingManager.swift",
                "Core/RelayConnection.swift",
                "Core/SessionManager.swift",
                "Features/Agent/ApprovalManager.swift",
            ]
        ),
        // Claude 终端输出解析逻辑（纯 Foundation，可独立在 macOS 上测试）
        .target(
            name: "cmuxClaudeCore",
            dependencies: [],
            path: "Sources/Features/Claude",
            exclude: [
                "ChatInputBar.swift",
                "ChatMessageRow.swift",
                "ClaudeChatView.swift",
                "ComposeInputView.swift",
                "ComposeInputViewModel.swift",
                "FileMentionPicker.swift",
                "MarkdownView.swift",
                "SlashCommandMenu.swift",
                "TaskTreeView.swift",
                "ToolDetailView.swift",
                "TurnView.swift",
                "ToolRenderers",
            ],
            sources: [
                "ClaudeMessage.swift",
                "ClaudeOutputParser.swift",
            ]
        ),
        // 模型单元测试：仅包含不依赖 UIKit 的纯模型测试
        .testTarget(
            name: "cmux-mobileTests",
            dependencies: ["cmux-models", "cmux-core", "cmuxClaudeCore"],
            path: "Tests",
            exclude: [
                "ANSIParserTests.swift",
                "MessageStoreTests.swift",
                "SyntaxHighlighterTests.swift",
            ],
            sources: [
                "AnyCodableTests.swift",
                "ApprovalManagerTests.swift",
                "ClaudeOutputParserTests.swift",
                "ClaudeChatItemTests.swift",
                "ClaudeChatItemCodableTests.swift",
                "ClaudeHistoryPagingStateTests.swift",
                "ConnectionStatusTests.swift",
                "ContentBlockTests.swift",
                "DeviceStoreTests.swift",
                "DisconnectRecoveryTests.swift",
                "E2ECryptoManagerTests.swift",
                "InputManagerTests.swift",
                "ConversationTurnTests.swift",
                "ConversationTurnEdgeCaseTests.swift",
                "LatestOnlyRequestGateTests.swift",
                "OfflineMessageQueueTests.swift",
                "PairingManagerTests.swift",
                "RelayConnectionTests.swift",
                "RpcDedupTests.swift",
                "RpcDedupCacheEdgeTests.swift",
                "SessionManagerTests.swift",
            ]
        ),
    ]
)
