// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "GitRanger",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "GitRanger",
            path: "Sources/GitRanger",
            resources: [
                .copy("Resources/AppIcon.icns"),
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/MenuBarIcon@2x.png")
            ]
        ),
        .testTarget(
            name: "GitRangerTests",
            dependencies: ["GitRanger"],
            path: "Tests/GitRangerTests"
        )
    ]
)
