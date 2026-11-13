// swift-tools-version: 6.0
import PackageDescription

// Pure, platform-API-free logic: models, search ranking, grid navigation,
// MRU ordering, shortcut model. Tested with `swift test`.
let package = Package(
    name: "SwoopCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SwoopCore", targets: ["SwoopCore"]),
    ],
    targets: [
        .target(name: "SwoopCore"),
        .testTarget(name: "SwoopCoreTests", dependencies: ["SwoopCore"]),
    ]
)
