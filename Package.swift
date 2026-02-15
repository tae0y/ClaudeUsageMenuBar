// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ClaudeUsageMenuBar",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClaudeUsageMenuBar", targets: ["ClaudeUsageMenuBarApp"]),
    ],
    targets: [
        .target(
            name: "ClaudeUsageMenuBarCore",
            path: "Sources/ClaudeUsageMenuBarCore"
        ),
        .executableTarget(
            name: "ClaudeUsageMenuBarApp",
            dependencies: ["ClaudeUsageMenuBarCore"],
            path: "Sources/ClaudeUsageMenuBarApp"
        ),
    ]
)
