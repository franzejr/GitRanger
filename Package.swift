// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitNarrate",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GitNarrate",
            path: "Sources/GitNarrate",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png")
            ]
        ),
        .testTarget(
            name: "GitNarrateTests",
            dependencies: ["GitNarrate"],
            path: "Tests/GitNarrateTests"
        )
    ]
)
