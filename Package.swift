// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacOSRemote",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "MacOSRemote",
            targets: ["MacOSRemote"]
        ),
    ],
    targets: [
        .target(
            name: "MacOSRemote",
            path: "src/macos-remote"
        ),
        .testTarget(
            name: "MacOSRemoteTests",
            dependencies: ["MacOSRemote"],
            path: "tests/macos-remoteTests"
        ),
    ],
    swiftLanguageModes: [.v6]
)
