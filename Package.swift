// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacBuds",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BudsProtocol", targets: ["BudsProtocol"]),
        .library(name: "BudsTransport", targets: ["BudsTransport"]),
        .executable(name: "macbuds", targets: ["macbuds"]),
        .executable(name: "MacBudsApp", targets: ["MacBudsApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(name: "BudsProtocol"),
        .target(
            name: "BudsTransport",
            dependencies: ["BudsProtocol"],
            linkerSettings: [.linkedFramework("IOBluetooth")]
        ),
        .executableTarget(
            name: "macbuds",
            dependencies: [
                "BudsTransport",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(name: "MacBudsApp", dependencies: ["BudsTransport"]),
        .testTarget(name: "BudsProtocolTests", dependencies: ["BudsProtocol"]),
        .testTarget(name: "BudsTransportTests", dependencies: ["BudsTransport"]),
    ],
    swiftLanguageModes: [.v6]
)
