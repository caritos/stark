// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StarkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StarkKit", targets: ["StarkKit"]),
        .library(name: "StarkClaudeCore", targets: ["StarkClaudeCore"]),
        .executable(name: "stark-claude", targets: ["stark-claude"])
    ],
    targets: [
        .target(name: "StarkKit"),
        .testTarget(name: "StarkKitTests", dependencies: ["StarkKit"]),
        .target(name: "StarkClaudeCore", dependencies: ["StarkKit"]),
        .executableTarget(name: "stark-claude", dependencies: ["StarkClaudeCore", "StarkKit"]),
        .testTarget(name: "StarkClaudeCoreTests", dependencies: ["StarkClaudeCore", "StarkKit"])
    ]
)
