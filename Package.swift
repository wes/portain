// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Portain",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Portain", targets: ["Portain"]),
        .executable(name: "PortainMenuBar", targets: ["PortainMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "Portain",
            path: "Sources/Portain"
        ),
        .executableTarget(
            name: "PortainMenuBar",
            path: "Sources/PortainMenuBar"
        )
    ]
)
