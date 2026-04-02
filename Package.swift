// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "OpenReading",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "OpenReading",
            targets: ["OpenReading"]
        )
    ],
    targets: [
        .executableTarget(
            name: "OpenReading"
        )
    ]
)
