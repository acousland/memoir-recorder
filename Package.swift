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
    targets: [
        .executableTarget(
            name: "MemoirRecorderApp",
            path: "Sources/MemoirRecorderApp"
        ),
        .testTarget(
            name: "MemoirRecorderAppTests",
            dependencies: ["MemoirRecorderApp"],
            path: "Tests/MemoirRecorderAppTests"
        )
    ]
)
