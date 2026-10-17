// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "GreenCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "GreenCore", targets: ["GreenCore"]),
        .library(name: "GreenCoreFakes", targets: ["GreenCoreFakes"]),
    ],
    targets: [
        .target(name: "GreenCore"),
        .target(name: "GreenCoreFakes", dependencies: ["GreenCore"]),
        .testTarget(name: "GreenCoreTests", dependencies: ["GreenCore", "GreenCoreFakes"],
                    resources: [.copy("Fixtures")]),
    ]
)
