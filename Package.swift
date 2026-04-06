// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cmux-mobile",
    platforms: [.iOS(.v17), .macOS(.v13)],
    targets: [
        // 核心 library target（可测试）
        .target(
            name: "cmux-mobile",
            dependencies: [],
            path: "Sources"
        ),
        // iOS App 入口（独立 target，不参与 macOS 测试链接）
        .executableTarget(
            name: "cmux-mobile-app",
            dependencies: ["cmux-mobile"],
            path: "App"
        ),
        .testTarget(
            name: "cmux-mobileTests",
            dependencies: ["cmux-mobile"],
            path: "Tests"
        ),
    ]
)
