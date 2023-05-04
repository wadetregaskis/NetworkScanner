// swift-tools-version: 5.8

import PackageDescription

let package = Package(
    name: "NetworkScanner",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
        .macCatalyst(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [
        .library(
            name: "NetworkScanner",
            targets: ["NetworkScanner"]),
        .executable(
            name: "NetworkScannerDemo",
            targets: ["NetworkScannerDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "0.0.0")),
        .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/wadetregaskis/NetworkInterfaceInfo.git", .upToNextMajor(from: "2.0.0")),
    ],
    targets: [
        .target(
            name: "NetworkScanner",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NetworkInterfaceInfo", package: "NetworkInterfaceInfo"),
                .product(name: "NetworkInterfaceChangeMonitoring", package: "NetworkInterfaceInfo")]),
        .executableTarget(
            name: "NetworkScannerDemo",
            dependencies: ["NetworkScanner"]),
    ]
)
