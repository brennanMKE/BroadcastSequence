// swift-tools-version: 5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BroadcastSequence",
    platforms: [.iOS(.v13), .macOS(.v12)],
    products: [
        .library(
            name: "BroadcastSequence",
            targets: ["BroadcastSequence"]),
    ],
    dependencies: [
        .package(url: "https://github.com/brennanMKE/AsyncTesting.git", exact: "0.0.7")
    ],
    targets: [
        // Targets are the basic building blocks of a package. A target can define a module or a test suite.
        // Targets can depend on other targets in this package, and on products in packages this package depends on.
        .target(
            name: "BroadcastSequence",
            dependencies: []),
        .testTarget(
            name: "BroadcastSequenceTests",
            dependencies: ["BroadcastSequence", "AsyncTesting"]),
    ]
)
