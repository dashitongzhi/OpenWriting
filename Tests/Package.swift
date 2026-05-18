// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWritingTests",
    platforms: [.macOS(.v14)],
    products: [
        .executable(
            name: "TestHost",
            targets: ["TestHost"]
        )
    ],
    targets: [
        .target(
            name: "TestHost",
            dependencies: [
                .target(name: "OpenWritingTests")
            ]
        ),
        .testTarget(
            name: "OpenWritingTests",
            dependencies: ["OpenWriting"],
            path: "Tests/OpenWritingTests"
        )
    ]
)