// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Portain",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Portain",
            path: "Sources/Portain"
        )
    ]
)
