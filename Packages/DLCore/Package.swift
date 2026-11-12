// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DLCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "DLCore", targets: ["DLCore"])],
    // Schnorr signatures over secp256k1 for Nostr (owner approved 2026-11-07). Pinned exactly.
    dependencies: [.package(url: "https://github.com/21-DOT-DEV/swift-secp256k1", exact: "0.24.0")],
    targets: [
        .target(
            name: "DLCore",
            dependencies: [.product(name: "P256K", package: "swift-secp256k1")],
            resources: [.copy("Resources/words.txt"), .copy("Resources/dictionary.txt")],
            swiftSettings: [.unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(name: "DLCoreTests", dependencies: ["DLCore"], exclude: ["vectors.json"]),
    ]
)
