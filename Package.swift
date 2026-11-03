// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "pkexec",
    platforms: [.macOS(.v26)],
    targets: [
        .target(name: "PkexecCore"),
        .executableTarget(name: "pkexec", dependencies: ["PkexecCore"]),
        .testTarget(name: "PkexecCoreTests", dependencies: ["PkexecCore"]),
    ]
)
