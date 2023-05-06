// swift-tools-version: 5.8

import PackageDescription

let swiftSettings: [SwiftSetting] = [
   .enableUpcomingFeature("BareSlashRegexLiterals"),
   .enableUpcomingFeature("ConciseMagicFile"),
   .enableUpcomingFeature("ExistentialAny"),
   .enableUpcomingFeature("ForwardTrailingClosures"),
   .enableUpcomingFeature("ImplicitOpenExistentials"),
   .enableUpcomingFeature("StrictConcurrency"),
   // Sadly StrictConcurrency isn't actually recognised by the Swift compiler as an upcoming feature, due to an apparent oversight by the compiler team.  So "unsafe" flags have to be used.  But if you do use them, you can't then actually _use_ the package from any other package - the Swift Package Manager will throw up all over the idea with compiler errors.  Sigh.
   //.unsafeFlags(["-Xfrontend", "-strict-concurrency=complete", "-enable-actor-data-race-checks"]),
]

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
        .package(url: "https://github.com/wadetregaskis/NetworkInterfaceInfo.git", .upToNextMajor(from: "4.0.0")),
    ],
    targets: [
        .target(
            name: "NetworkScanner",
            dependencies: [
                .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "NetworkInterfaceInfo", package: "NetworkInterfaceInfo"),
                .product(name: "NetworkInterfaceChangeMonitoring", package: "NetworkInterfaceInfo")],
            swiftSettings: swiftSettings),
        .executableTarget(
            name: "NetworkScannerDemo",
            dependencies: ["NetworkScanner"],
            swiftSettings: swiftSettings),
    ]
)
