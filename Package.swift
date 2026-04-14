// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Deck",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(url: "https://github.com/LebJe/TOMLKit", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "GhosttyKit",
            path: "GhosttyKit",
            publicHeadersPath: "."
        ),
        .target(
            name: "DeckLib",
            dependencies: ["GhosttyKit", "TOMLKit"],
            path: "Sources/DeckLib",
            linkerSettings: [
                .unsafeFlags([
                    "-L", "GhosttyKit.xcframework/macos-arm64_x86_64",
                    "-lghostty",
                ]),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("CoreText"),
                .linkedFramework("Foundation"),
                .linkedFramework("IOKit"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("QuartzCore"),
                .linkedLibrary("c++"),
            ]
        ),
        .executableTarget(
            name: "Deck",
            dependencies: ["DeckLib"],
            path: "Sources/DeckApp"
        ),
        .testTarget(
            name: "DeckTests",
            dependencies: ["DeckLib"],
            path: "Tests"
        ),
    ]
)
