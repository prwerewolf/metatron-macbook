// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PressToWrite",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PressToWrite", targets: ["PressToWrite"])
    ],
    targets: [
        .executableTarget(
            name: "PressToWrite",
            path: "Sources/PressToWrite"
        )
    ]
)
