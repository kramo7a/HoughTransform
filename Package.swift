// swift-tools-version: 5.10
import PackageDescription

let package = Package(
  name: "HoughTransform",
  platforms: [
    .iOS(.v17),
    .macOS(.v14),
    .visionOS(.v1)
  ],
  products: [
    .library(
      name: "HoughTransform",
      targets: ["HoughTransform"])
  ],
  dependencies: [
    .package(url: "https://github.com/hmlongco/Factory.git", from: "2.5.3")
  ],
  targets: [
    .target(
      name: "HoughTransform",
      dependencies: [
        .product(name: "FactoryKit", package: "Factory")
      ]
    )
  ]
)
