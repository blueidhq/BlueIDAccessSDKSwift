// swift-tools-version:5.8

import PackageDescription

let package = Package(
  name: "BlueIDAccessSDK",
  platforms: [
    .macOS(.v12),
    .iOS("15.5"),
    .watchOS(.v8),
  ],
  products: [
    .library(
      name: "BlueIDAccessSDK",
      targets: ["BlueIDAccessSDK", "CBlueIDAccess"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.24.0"),
    .package(url: "https://github.com/NordicSemiconductor/IOS-DFU-Library", from: "4.15.0")
  ],
  targets: [
    .target(
      name: "BlueIDAccessSDK",
      dependencies: [
        "CBlueIDAccess",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
        .product(name: "NordicDFU", package: "IOS-DFU-Library")
      ]
    ),
    .binaryTarget(
      name: "CBlueIDAccess",
      path: "./CBlueIDAccess.xcframework"
    ),
    .testTarget(
      name: "BlueIDAccessSDKTests",
      dependencies: ["BlueIDAccessSDK"]
    ),
  ]
)
