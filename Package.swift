// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "notype",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(
            name: "NoType",
            targets: ["NoType"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "NoType",
            path: "Sources/notype",
            exclude: [
                "Resources/Info.plist",
                "Resources/AppIcon.icns",
                "Resources/AppIcon.iconset",
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("Speech"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Translation"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/notype/Resources/Info.plist",
                ]),
            ]
        ),
    ]
)
