// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "logic-cli",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "logic", targets: ["LogicCLI"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(name: "MIDIKit"),
        .target(name: "LogicKit"),
        .executableTarget(
            name: "LogicCLI",
            dependencies: [
                "MIDIKit",
                "LogicKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(name: "MIDIKitTests", dependencies: ["MIDIKit"]),
    ]
)
