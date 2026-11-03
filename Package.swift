// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "pkexec",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "PkexecCore"),
        .executableTarget(name: "pkexec", dependencies: ["PkexecCore"]),
        .testTarget(name: "PkexecCoreTests", dependencies: ["PkexecCore"]),
    ]
)
