// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "cmux-mobile",
    platforms: [.iOS(.v17)],
    targets: [
        .executableTarget(
            name: "cmux-mobile",
            dependencies: [],
            path: "Sources"
        ),
        .testTarget(
            name: "cmux-mobileTests",
            dependencies: ["cmux-mobile"],
            path: "Tests"
        ),
    ]
)
