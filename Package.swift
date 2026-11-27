// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "downbeat",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "downbeat", targets: ["DownbeatCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "MIDIKit"),
        .target(name: "DownbeatKit"),
        .executableTarget(
            name: "DownbeatCLI",
            dependencies: [
                "MIDIKit",
                "DownbeatKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MIDIKitTests", dependencies: ["MIDIKit"]),
        .testTarget(name: "DownbeatKitTests", dependencies: ["DownbeatKit"]),
    ]
)
