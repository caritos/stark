// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "StarkKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StarkKit", targets: ["StarkKit"])
    ],
    targets: [
        .target(name: "StarkKit"),
        .testTarget(name: "StarkKitTests", dependencies: ["StarkKit"])
    ]
)
