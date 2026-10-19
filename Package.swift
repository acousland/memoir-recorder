// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MemoirRecorder",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "MemoirRecorderApp", targets: ["MemoirRecorderApp"])
    ],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.6")],
    targets: [
        .executableTarget(
            name: "MemoirRecorderApp",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/MemoirRecorderApp"
        ),
        .testTarget(
            name: "MemoirRecorderAppTests",
            dependencies: ["MemoirRecorderApp"],
            path: "Tests/MemoirRecorderAppTests"
        )
    ]
)
