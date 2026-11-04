// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "letmedo",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "LetmedoCore"),
        .executableTarget(name: "letmedo", dependencies: ["LetmedoCore"]),
        .testTarget(name: "LetmedoCoreTests", dependencies: ["LetmedoCore"]),
    ]
)
