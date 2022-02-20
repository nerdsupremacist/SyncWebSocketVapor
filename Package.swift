// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SyncWebSocketVapor",
    platforms: [.macOS(.v11), .iOS(.v14), .watchOS(.v6), .tvOS(.v14)],
    products: [
        .library(
            name: "SyncWebSocketVapor",
            targets: ["SyncWebSocketVapor"]),
    ],
    dependencies: [
        .package(name: "Sync", url: "https://github.com/nerdsupremacist/Sync.git", from: "0.1.0"),
        .package(url: "https://github.com/vapor/vapor.git", .upToNextMajor(from: "4.0.0")),
    ],
    targets: [
        .target(
            name: "SyncWebSocketVapor",
            dependencies: [
                "Sync",
                .product(name: "Vapor", package: "vapor"),
            ]),
    ]
)
