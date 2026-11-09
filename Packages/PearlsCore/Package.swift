// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PearlsCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "PearlsCore", targets: ["PearlsCore"])],
    targets: [
        .target(name: "PearlsCore"),
        .testTarget(name: "PearlsCoreTests", dependencies: ["PearlsCore"])
    ]
)
