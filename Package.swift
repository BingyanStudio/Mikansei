// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MikanseiCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "MikanseiCore", targets: ["MikanseiCore"])],
    targets: [
        .target(name: "MikanseiCore"),
        .testTarget(name: "MikanseiCoreTests", dependencies: ["MikanseiCore"])
    ]
)
