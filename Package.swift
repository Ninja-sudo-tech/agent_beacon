// swift-tools-version: 5.8
import PackageDescription

let package = Package(
    name: "AgentBeacon",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "Core",
            path: "Sources/Core"
        ),
        .executableTarget(
            name: "agent-beacon",
            dependencies: ["Core"],
            path: "Sources/CLI"
        ),
        .executableTarget(
            name: "AgentBeaconApp",
            dependencies: ["Core"],
            path: "Sources/App",
            swiftSettings: [
                .unsafeFlags(["-framework", "AppKit"])
            ]
        ),
        .testTarget(
            name: "CoreTests",
            dependencies: ["Core"],
            path: "Tests"
        )
    ]
)
