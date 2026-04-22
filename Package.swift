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
            name: "PersonalScribeSession",
            dependencies: [
                "PersonalScribeCore",
                "PersonalScribeAudio",
                "PersonalScribeTranscription",
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
            ],
            path: "Sources/PersonalScribeAppKit",
            resources: [
                .process("Resources"),
            ]
        ),
        // `exclude:` keeps Manual*Verification.md runbooks in the test
        // target directory (next to the related tests, where they're
        // discoverable) without SwiftPM complaining about unhandled
        // files. These are plaintext docs — not resources, not tests.
        .testTarget(
            name: "PersonalScribeCoreTests",
            dependencies: [
                "PersonalScribeCore",
            ],
            path: "Tests/PersonalScribeCoreTests",
            exclude: [
                "ManualConfigVerification.md",
            ]
        ),
        .testTarget(
            name: "PersonalScribeAudioTests",
            dependencies: [
                "PersonalScribeAudio",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeAudioTests",
            exclude: [
                "ManualAudioCaptureVerification.md",
                "ManualAudioLevelVerification.md",
            ]
        ),
        .testTarget(
            name: "PersonalScribeTranscriptionTests",
            dependencies: [
                "PersonalScribeTranscription",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeTranscriptionTests",
            exclude: [
                "ManualTranscriptionVerification.md",
            ]
        ),
        .testTarget(
            name: "PersonalScribeSessionTests",
            dependencies: [
                "PersonalScribeSession",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeSessionTests"
        ),
        .testTarget(
            name: "PersonalScribeAppKitTests",
            dependencies: [
                "PersonalScribeAppKit",
                "PersonalScribeTestSupport",
            ],
            path: "Tests/PersonalScribeAppKitTests",
            exclude: [
                "ManualCompositesVerification.md",
                "ManualHotkeyVerification.md",
                "ManualNotesVerification.md",
                "ManualPillOverlayVerification.md",
                "ManualSettingsVerification.md",
                "ManualSQLiteVerification.md",
                "ManualStatusItemVerification.md",
                "ManualTranscriptionsVerification.md",
                "ManualVisualVerification.md",
                "ManualWeek1Verification.md",
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)
