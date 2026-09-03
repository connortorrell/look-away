// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LookAway",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "LookAwayCore"),
        .executableTarget(name: "LookAway", dependencies: ["LookAwayCore"]),
        .testTarget(name: "LookAwayCoreTests", dependencies: ["LookAwayCore"]),
    ]
)
