// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "BlueIDAccessSDK",
    platforms: [
      .macOS(.v12),
      .iOS(.v14),
      .watchOS(.v8),
    ],
    products: [
        .library(
            name: "BlueIDAccessSDK",
            targets: ["BlueIDAccessSDKLib", "BlueIDAccessSDKFramework"]
        ),
    ],
    dependencies: [
      .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.24.0"),
      .package(url: "https://github.com/NordicSemiconductor/IOS-DFU-Library", from: "4.15.0"),
      .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.28.0")
    ],
    targets: [
        .target(
            name: "BlueIDAccessSDKLib",
            dependencies: [
              .product(name: "SwiftProtobuf", package: "swift-protobuf"),
              .product(name: "NordicDFU", package: "IOS-DFU-Library"),
              .product(name: "Sentry", package: "sentry-cocoa")
            ]
        ),
        .binaryTarget(
            name: "BlueIDAccessSDKFramework",
            path: "./BlueIDAccessSDK.xcframework"
        )
    ]
)
