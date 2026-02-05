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
      .package(url: "https://github.com/apple/swift-protobuf.git", .upToNextMajor(from: "1.31.0")),
      .package(url: "https://github.com/NordicSemiconductor/IOS-DFU-Library", .upToNextMajor(from: "4.15.0")),
    ],
    targets: [
        .target(
            name: "BlueIDAccessSDKLib",
            dependencies: [
              .product(name: "SwiftProtobuf", package: "swift-protobuf"),
              .product(name: "NordicDFU", package: "IOS-DFU-Library")
            ]
        ),
        .binaryTarget(
            name: "BlueIDAccessSDKFramework",
            path: "./BlueIDAccessSDK.xcframework"
        )
    ]
)
