// swift-tools-version:5.9
import PackageDescription

// Reads DLChat's anonymous support reports on the developer's Mac. Not part of the app.
let package = Package(
    name: "support-reports",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "../../Packages/DLCore")],
    targets: [.executableTarget(name: "support-reports", dependencies: [.product(name: "DLCore", package: "DLCore")])]
)
