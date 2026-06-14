// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWritingXcodeOnlyTests",
    platforms: [.macOS(.v14)],
    products: [],
    targets: [
        .target(
            name: "XcodeOnlyPlaceholder",
            path: "SwiftPMPlaceholder"
        )
    ]
)
