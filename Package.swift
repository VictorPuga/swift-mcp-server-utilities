// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "SwiftMCPServerUtilities",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ScalekitAuth",
            targets: ["ScalekitAuth"]
        ),
        .library(
            name: "GoogleCloudAuth",
            targets: ["GoogleCloudAuth"]
        ),
        .library(
            name: "GCPSecretManager",
            targets: ["GCPSecretManager"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1"),
        .package(url: "https://github.com/vapor/jwt-kit.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "4.5.1"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "ScalekitAuth",
            dependencies: [
                .product(name: "JWTKit", package: "jwt-kit"),
                .product(name: "MCP", package: "swift-sdk"),
            ]
        ),
        .target(
            name: "GoogleCloudAuth",
            dependencies: [
                .product(name: "JWTKit", package: "jwt-kit")
            ]
        ),
        .target(
            name: "GCPSecretManager",
            dependencies: [
                "GoogleCloudAuth"
            ]
        ),
        .testTarget(
            name: "ScalekitAuthTests",
            dependencies: ["ScalekitAuth"]
        ),
        .testTarget(
            name: "GoogleCloudAuthTests",
            dependencies: [
                "GoogleCloudAuth",
                .product(name: "_CryptoExtras", package: "swift-crypto"),
            ]
        ),
        .testTarget(
            name: "GCPSecretManagerTests",
            dependencies: ["GCPSecretManager"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
