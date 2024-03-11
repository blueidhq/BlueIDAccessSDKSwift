// swift-tools-version:5.8

import PackageDescription

let package = Package(
  name: "BlueIDAccessSDK",
  platforms: [
    .macOS(.v10_15),
    .iOS(.v14),
    .watchOS(.v8),
  ],
  products: [
    .library(
      name: "BlueIDAccessSDK",
      targets: ["BlueIDAccessSDK", "CBlueIDAccess"]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.24.0")
  ],
  targets: [
    .target(
      name: "BlueIDAccessSDK",
      dependencies: [
        "CBlueIDAccess",
        .product(name: "SwiftProtobuf", package: "swift-protobuf"),
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
