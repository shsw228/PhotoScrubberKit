// swift-tools-version: 6.2

import AppleProductTypes
import PackageDescription

let package = Package(
    name: "PhotoScrubberKitPlayground",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .iOSApplication(
            name: "PhotoScrubberKitPlayground",
            targets: ["AppModule"],
            bundleIdentifier: "dev.hume.PhotoScrubberKitPlayground",
            teamIdentifier: "",
            displayVersion: "1.0",
            bundleVersion: "1",
            appIcon: .placeholder(icon: .images),
            accentColor: .presetColor(.teal),
            supportedDeviceFamilies: [.pad, .phone],
            supportedInterfaceOrientations: [
                .portrait,
                .landscapeRight,
                .landscapeLeft,
                .portraitUpsideDown(.when(deviceFamilies: [.pad]))
            ]
        )
    ],
    dependencies: [
        .package(name: "PhotoScrubberKit", path: "../")
    ],
    targets: [
        .executableTarget(
            name: "AppModule",
            dependencies: [
                .product(name: "PhotoScrubberKit", package: "PhotoScrubberKit")
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
