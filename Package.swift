// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "md-reader",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "MDReaderKit",
            path: "Sources/MDReaderKit",
            resources: [.copy("Resources/web")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "MDReader",
            dependencies: ["MDReaderKit"],
            path: "Sources/MDReader",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "MDReaderTests",
            dependencies: ["MDReaderKit"],
            path: "Tests/MDReaderTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
