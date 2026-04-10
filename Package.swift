// swift-tools-version: 5.9
import PackageDescription

// 注意：iOS 相关 target (cmux-mobile, cmux-mobile-app) 通过 Xcode / project.yml 构建。
// Package.swift 仅用于 macOS 上 `swift test` 运行纯模型测试。
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
        // 模型单元测试：仅包含不依赖 UIKit 的纯模型测试
        .testTarget(
            name: "cmux-mobileTests",
            dependencies: ["cmux-models"],
            path: "Tests",
            sources: [
                "AnyCodableTests.swift",
                "ClaudeChatItemTests.swift",
                "ContentBlockTests.swift",
                "ConversationTurnTests.swift",
                "ConversationTurnEdgeCaseTests.swift",
                "RpcDedupTests.swift",
                "RpcDedupCacheEdgeTests.swift",
            ]
        ),
    ]
)
