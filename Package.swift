// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cmux-mobile",
    // macOS 平台用于 swift test（纯模型测试）；iOS 用于实际 App 构建
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        // 纯 Swift 模型 target（无 UIKit 依赖，macOS/iOS 均可编译）
        .target(
            name: "cmux-models",
            dependencies: [],
            path: "Sources/Models"
        ),
        // 单元测试：只依赖纯模型 target，macOS 上可通过 swift test 运行
        // 仅包含不依赖 UIKit 的测试文件
        .testTarget(
            name: "cmux-mobileTests",
            dependencies: ["cmux-models"],
            path: "Tests",
            sources: [
                "ClaudeChatItemTests.swift",
                "ContentBlockTests.swift",
                "ConversationTurnTests.swift",
            ]
        ),
    ]
)
