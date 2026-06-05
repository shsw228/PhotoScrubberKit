// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhotoScrubberKit",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "PhotoScrubberKit", targets: ["PhotoScrubberKit"])
    ],
    targets: [
        .target(name: "PhotoScrubberKit"),
        .testTarget(name: "PhotoScrubberKitTests", dependencies: ["PhotoScrubberKit"])
    ]
)
