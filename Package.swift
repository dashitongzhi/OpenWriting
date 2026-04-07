// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenWriting",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenWriting",
            targets: ["OpenWriting"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenWriting",
            path: "Sources/OpenWriting",
            resources: [
                .process("Resources")
            ]
        )
    ]
)
