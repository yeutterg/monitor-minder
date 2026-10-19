// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MonitorMinder",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "MonitorMinder", targets: ["MonitorMinder"]),
    ],
    targets: [
        // Reading and applying display arrangements, moving windows, and the config file. No UI.
        .target(name: "MonitorMinderCore"),
        .executableTarget(name: "MonitorMinder", dependencies: ["MonitorMinderCore"]),
        .testTarget(name: "MonitorMinderCoreTests", dependencies: ["MonitorMinderCore"]),
    ]
)
