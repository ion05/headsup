// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HeadsUp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "HeadsUp", swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "HeadsUpTests", dependencies: ["HeadsUp"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
