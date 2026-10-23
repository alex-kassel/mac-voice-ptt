// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Dictaphone",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Dictaphone",
            targets: ["Dictaphone"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Dictaphone",
            path: "Sources/Dictaphone"
        )
    ]
)
