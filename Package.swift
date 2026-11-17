// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HotkeyShow",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HotkeyShow", targets: ["HotkeyShow"])
    ],
    targets: [
        .executableTarget(
            name: "HotkeyShow",
            path: "Sources/HotkeyShow"
        ),
        .testTarget(
            name: "HotkeyShowTests",
            dependencies: ["HotkeyShow"],
            path: "Tests/HotkeyShowTests"
        )
    ]
)
