// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PersonalScribe",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "PersonalScribeCore",
            targets: ["PersonalScribeCore"]
        ),
        .library(
            name: "PersonalScribeAudio",
            targets: ["PersonalScribeAudio"]
        ),
        .library(
            name: "PersonalScribeTranscription",
            targets: ["PersonalScribeTranscription"]
        ),
        .library(
            name: "PersonalScribeVAD",
            targets: ["PersonalScribeVAD"]
        ),
        .library(
            name: "PersonalScribeSession",
            targets: ["PersonalScribeSession"]
        ),
        .library(
            name: "PersonalScribeTestSupport",
            targets: ["PersonalScribeTestSupport"]
        ),
        .executable(
            name: "PersonalScribeAppKit",
            targets: ["PersonalScribeAppKit"]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.13.6"
        ),
        .package(
            url: "https://github.com/groue/GRDB.swift.git",
            exact: "7.10.0"
        ),
    ],
    targets: [
        .target(
            name: "PersonalScribeCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/PersonalScribeCore"
        ),
        .target(
            name: "PersonalScribeAudio",
            dependencies: [
                "PersonalScribeCore",
            ],
            path: "Sources/PersonalScribeAudio"
        ),
        .target(
            name: "PersonalScribeTranscription",
            dependencies: [
                "PersonalScribeCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/PersonalScribeTranscription"
        ),
        .target(
            name: "PersonalScribeVAD",
            dependencies: [
                "PersonalScribeCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/PersonalScribeVAD",
            resources: [
                .copy("Resources/silero-vad.mlmodelc"),
            ]
        ),
        .target(
            name: "PersonalScribeSession",
            dependencies: [
                "PersonalScribeCore",
                "PersonalScribeAudio",
                "PersonalScribeTranscription",
                "PersonalScribeVAD",
            ],
            path: "Sources/PersonalScribeSession"
        ),
        .target(
            name: "PersonalScribeTestSupport",
            dependencies: [
                "PersonalScribeCore",
            ],
            path: "Sources/PersonalScribeTestSupport"
        ),
        .executableTarget(
            name: "PersonalScribeAppKit",
            dependencies: [
                "PersonalScribeCore",
                "PersonalScribeSession",
                "PersonalScribeAudio",
                "PersonalScribeTranscription",
                "PersonalScribeVAD",
            ],
            path: "Sources/PersonalScribeAppKit",
            resources: [
                .process("Resources"),
            ]
        ),
        // Manual*Verification.md runbooks now live under
        // `Tests/ManualVerifications/`, out of every test target's source
        // path. SwiftPM no longer sees them so no `exclude:` entries
        // needed. They're plaintext dev/QA docs — not resources, not tests.
        .testTarget(
            name: "PersonalScribeCoreTests",
            dependencies: [
                "PersonalScribeCore",
            ],
            path: "Tests/PersonalScribeCoreTests"
        ),
        .testTarget(
            name: "PersonalScribeAudioTests",
            dependencies: [
                "PersonalScribeAudio",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeAudioTests"
        ),
        .testTarget(
            name: "PersonalScribeTranscriptionTests",
            dependencies: [
                "PersonalScribeTranscription",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeTranscriptionTests"
        ),
        .testTarget(
            name: "PersonalScribeVADTests",
            dependencies: [
                "PersonalScribeVAD",
            ],
            path: "Tests/PersonalScribeVADTests"
        ),
        .testTarget(
            name: "PersonalScribeSessionTests",
            dependencies: [
                "PersonalScribeSession",
                "PersonalScribeTestSupport",
                "PersonalScribeVAD",
            ],
            path: "Tests/PersonalScribeSessionTests"
        ),
        .testTarget(
            name: "PersonalScribeAppKitTests",
            dependencies: [
                "PersonalScribeAppKit",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeAppKitTests"
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
