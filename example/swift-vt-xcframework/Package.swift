// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-vt-xcframework",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "swift-vt-xcframework",
            dependencies: ["XGhosttyVt"],
            path: "Sources"
        ),
        .binaryTarget(
            name: "XGhosttyVt",
            path: "../../zig-out/lib/ghostty-vt.xcframework"
        ),
    ]
)
