// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "vibecodeMaxing",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "vibecodeMaxing", targets: ["Afterglow"]),
        .executable(name: "vibecodeMaxingGuard", targets: ["AfterglowGuard"])
    ],
    targets: [
        .target(name: "AfterglowCore"),
        .executableTarget(name: "Afterglow", dependencies: ["AfterglowCore"]),
        .executableTarget(name: "AfterglowGuard", dependencies: ["AfterglowCore"]),
        .testTarget(name: "AfterglowCoreTests", dependencies: ["AfterglowCore"])
    ]
)
