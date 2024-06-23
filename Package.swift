// swift-tools-version: 5.8

import PackageDescription

let enables = ["AccessLevelOnImport",
               "BareSlashRegexLiterals",
               "ConciseMagicFile",
               "DeprecateApplicationMain",
               "DisableOutwardActorInference",
               "DynamicActorIsolation",
               "ExistentialAny",
               "ForwardTrailingClosures",
               //"FullTypedThrows", // Not ready yet.  https://forums.swift.org/t/where-is-fulltypedthrows/72346/15
               "GlobalConcurrency",
               "ImplicitOpenExistentials",
               "ImportObjcForwardDeclarations",
               "InferSendableFromCaptures",
               "InternalImportsByDefault",
               "IsolatedDefaultValues",
               "StrictConcurrency"]

let settings: [SwiftSetting] = enables.flatMap {
    [.enableUpcomingFeature($0), .enableExperimentalFeature($0)]
}

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
        .package(url: "https://github.com/apple/swift-async-algorithms.git", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/apple/swift-log", .upToNextMajor(from: "1.0.0")),
        .package(url: "https://github.com/wadetregaskis/NetworkInterfaceInfo.git", .upToNextMajor(from: "5.0.0")),
    ],
    targets: [
        .target(
            name: "NetworkScanner",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NetworkInterfaceInfo", package: "NetworkInterfaceInfo"),
                .product(name: "NetworkInterfaceChangeMonitoring", package: "NetworkInterfaceInfo")],
            swiftSettings: settings),
        .executableTarget(
            name: "NetworkScannerDemo",
            dependencies: ["NetworkScanner"],
            swiftSettings: settings),
    ]
)
