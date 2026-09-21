// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Metatron",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Metatron", targets: ["Metatron"])
    ],
    targets: [
        .executableTarget(
            name: "Metatron",
            path: "Sources/Metatron"
        )
    ]
)
