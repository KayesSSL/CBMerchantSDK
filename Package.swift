// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CBMerchantSDK", // Your framework name
    platforms: [
        .iOS(.v15) // Specify the supported platforms
    ],
    products: [
        .library(
            name: "CBMerchantSDK",
            targets: ["CBMerchantSDK"]
        )
    ],
    targets: [
        .binaryTarget(
            name: "CBMerchantSDK",
            path: "./Framework/CBMerchantSDK.xcframework"
        )
    ]
)