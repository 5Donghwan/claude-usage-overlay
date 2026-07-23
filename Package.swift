// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClaudeUsageOverlay",
    platforms: [
        .macOS(.v14),
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsageOverlay",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
    ]
)
