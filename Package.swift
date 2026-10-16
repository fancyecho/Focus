// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Focus",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(name: "Focus", path: "Sources/Focus")
    ]
)
