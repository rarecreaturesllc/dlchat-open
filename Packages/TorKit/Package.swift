// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TorKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "TorKit", targets: ["TorKit"])],
    targets: [
        // iCepa Tor.framework v409.14.1, static: tor, OpenSSL, libevent, liblzma. scripts/fetch-tor.sh puts it here.
        .binaryTarget(name: "tor", path: "tor.xcframework"),
        .target(name: "TorKit", dependencies: ["tor"], linkerSettings: [.linkedLibrary("z")]),
        .testTarget(name: "TorKitTests", dependencies: ["TorKit"]),
    ]
)
