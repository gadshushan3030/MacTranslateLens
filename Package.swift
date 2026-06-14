// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacTranslateLens",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "MacTranslateLens", targets: ["MacTranslateLens"])
    ],
    targets: [
        .executableTarget(
            name: "MacTranslateLens",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision")
            ]
        )
    ]
)
