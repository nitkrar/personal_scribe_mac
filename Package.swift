// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Seshat",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SeshatCore",
            targets: ["SeshatCore"]
        ),
        .library(
            name: "SeshatAudio",
            targets: ["SeshatAudio"]
        ),
        .library(
            name: "SeshatTranscription",
            targets: ["SeshatTranscription"]
        ),
        .library(
            name: "SeshatSession",
            targets: ["SeshatSession"]
        ),
        .library(
            name: "SeshatTestSupport",
            targets: ["SeshatTestSupport"]
        ),
        .executable(
            name: "SeshatAppKit",
            targets: ["SeshatAppKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.13.6"
        ),
    ],
    targets: [
        .target(
            name: "SeshatCore",
            path: "Sources/SeshatCore"
        ),
        .target(
            name: "SeshatAudio",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatAudio"
        ),
        .target(
            name: "SeshatTranscription",
            dependencies: [
                "SeshatCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/SeshatTranscription"
        ),
        .target(
            name: "SeshatSession",
            dependencies: [
                "SeshatCore",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatSession"
        ),
        .target(
            name: "SeshatTestSupport",
            dependencies: [
                "SeshatCore",
            ],
            path: "Sources/SeshatTestSupport"
        ),
        .executableTarget(
            name: "SeshatAppKit",
            dependencies: [
                "SeshatCore",
                "SeshatSession",
                "SeshatAudio",
                "SeshatTranscription",
            ],
            path: "Sources/SeshatAppKit",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SeshatCoreTests",
            dependencies: [
                "SeshatCore",
            ],
            path: "Tests/SeshatCoreTests"
        ),
        .testTarget(
            name: "SeshatAudioTests",
            dependencies: [
                "SeshatAudio",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAudioTests"
        ),
        .testTarget(
            name: "SeshatTranscriptionTests",
            dependencies: [
                "SeshatTranscription",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatTranscriptionTests"
        ),
        .testTarget(
            name: "SeshatSessionTests",
            dependencies: [
                "SeshatSession",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatSessionTests"
        ),
        .testTarget(
            name: "SeshatAppKitTests",
            dependencies: [
                "SeshatAppKit",
                "SeshatTestSupport",
            ],
            path: "Tests/SeshatAppKitTests"
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
