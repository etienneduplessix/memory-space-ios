// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemorySpaceNearbyBridge",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MemorySpaceNearbyBridge", targets: ["MemorySpaceNearbyBridge"])
    ],
    targets: [
        .executableTarget(name: "MemorySpaceNearbyBridge")
    ]
)
