import XCTest
@testable import PersonalScribeCore

final class BuiltInModelCatalogTests: XCTestCase {
    func test110MDescriptorUsesPinnedRevisionAndFusedLayout() {
        let descriptor = BuiltInModelCatalog.parakeetTDTCTC110M

        XCTAssertEqual(descriptor.revision, "9bc92ead6e8f17eca92a869fd578ae76842b82ba")
        XCTAssertEqual(
            descriptor.requiredRelativePaths,
            [
                "Preprocessor.mlmodelc/coremldata.bin",
                "Decoder.mlmodelc/coremldata.bin",
                "JointDecision.mlmodelc/coremldata.bin",
                "parakeet_vocab.json",
            ]
        )
    }

    func testQwenDescriptorsUseFluidAudioTwoModelArtifactLayout() {
        let expectedPaths = [
            "qwen3_asr_audio_encoder_v2.mlmodelc/coremldata.bin",
            "qwen3_asr_decoder_stateful.mlmodelc/coremldata.bin",
            "qwen3_asr_embeddings.bin",
            "vocab.json",
        ]

        XCTAssertEqual(BuiltInModelCatalog.qwen3AsrF32.requiredRelativePaths, expectedPaths)
        XCTAssertEqual(BuiltInModelCatalog.qwen3AsrInt8.requiredRelativePaths, expectedPaths)
    }

    // MARK: - #007 — descriptive metadata for Settings AI Models tab

    /// Every registered model must carry a non-empty one-line
    /// description for the inline row copy. Guards against `ModelRow`
    /// rendering a blank second line if a new catalog entry forgets to
    /// fill the field in.
    func testAllRegisteredModelsHaveNonEmptyDescription() {
        for descriptor in BuiltInModelCatalog.registeredModels {
            XCTAssertFalse(
                descriptor.shortDescription.isEmpty,
                "\(descriptor.id) is missing an inline description"
            )
        }
    }

    /// Every registered model must declare an architecture label so
    /// the info popover's "Architecture" row has copy to render.
    func testAllRegisteredModelsDeclareArchitecture() {
        for descriptor in BuiltInModelCatalog.registeredModels {
            XCTAssertFalse(
                descriptor.architecture.isEmpty,
                "\(descriptor.id) missing architecture label"
            )
        }
    }

    /// Every enabled-kind model (today: `.asr`) must carry averageWER
    /// + rtfx so the computed-relative presenter can rank models
    /// without nil-fallback branches. Sourced from the HF Open ASR
    /// leaderboard — see the per-descriptor citation in
    /// `BuiltInModelCatalog.swift`. Non-enabled kinds (#024.10) ship
    /// without benchmarks today; they don't surface in the AI Models
    /// tab so the popover never reads their metrics.
    func testAllEnabledModelsCarryPublishedBenchmarks() {
        // Scope: parakeet TDT descriptors only. Qwen3 stays in the
        // registry and still ships without the benchmark metadata this
        // popover ranking consumes.
        let parakeetDescriptors = BuiltInModelCatalog.registeredModels
            .filter { $0.engine == .parakeetTDT }
        XCTAssertFalse(parakeetDescriptors.isEmpty)
        for descriptor in parakeetDescriptors {
            XCTAssertNotNil(
                descriptor.performance.averageWER,
                "\(descriptor.id) missing averageWER"
            )
            XCTAssertNotNil(
                descriptor.performance.rtfx,
                "\(descriptor.id) missing rtfx"
            )
        }
    }

    /// CTC-110M is meaningfully faster than the 0.6B variants
    /// (RTFx ~5345 vs ~3386/3333) and has noticeably worse accuracy
    /// (avg WER 7.49% vs 6.05%/6.34%). Pin this so a future careless
    /// edit can't flatten the axis that justifies the model's
    /// existence.
    func test110MHasHigherRTFxAndHigherWERThan06BV2() {
        let light = BuiltInModelCatalog.parakeetTDTCTC110M
        let standard = BuiltInModelCatalog.parakeetTDT06Bv2

        XCTAssertGreaterThan(
            light.performance.rtfx!,
            standard.performance.rtfx!,
            "CTC-110M should have higher RTFx than 0.6B v2"
        )
        XCTAssertGreaterThan(
            light.performance.averageWER!,
            standard.performance.averageWER!,
            "CTC-110M should have a worse (higher) WER than 0.6B v2"
        )
    }

    func testWhisperKitDescriptorsAreRegisteredAndEnabled() {
        let whisperKitDescriptors = BuiltInModelCatalog.registeredModels
            .filter { $0.engine == .whisperKit }
        let expectedIDs: Set<String> = [
            BuiltInModelCatalog.whisperKitTiny.id,
            BuiltInModelCatalog.whisperKitSmall216MB.id,
            BuiltInModelCatalog.whisperKitSmallEn217MB.id,
            BuiltInModelCatalog.whisperKitLargeV3626MB.id,
            BuiltInModelCatalog.whisperKitLargeV3Turbo632MB.id,
        ]

        XCTAssertEqual(Set(whisperKitDescriptors.map(\.id)), expectedIDs)
        for descriptor in whisperKitDescriptors {
            XCTAssertTrue(descriptor.isEnabled, "\(descriptor.id) should be live after #095 B.5")
        }
    }

    func testWhisperKitDescriptorsPinExpectedCatalogContract() {
        let commonRequiredPaths = [
            "AudioEncoder.mlmodelc/coremldata.bin",
            "MelSpectrogram.mlmodelc/coremldata.bin",
            "TextDecoder.mlmodelc/coremldata.bin",
            "config.json",
            "generation_config.json",
            "tokenizer/config.json",
            "tokenizer/tokenizer.json",
            "tokenizer/tokenizer_config.json",
            "tokenizer/vocab.json",
            "tokenizer/merges.txt",
            "tokenizer/added_tokens.json",
            "tokenizer/special_tokens_map.json",
            "tokenizer/normalizer.json",
        ]
        let expected: [(descriptor: ModelDescriptor, repoFolderName: String, tokenizerSource: String, worksWith: String, requiredChipFamily: ChipFamily?, requiredPaths: [String])] = [
            (
                BuiltInModelCatalog.whisperKitTiny,
                "openai_whisper-tiny",
                "openai/whisper-tiny",
                "Multilingual (~99 languages)",
                nil,
                commonRequiredPaths
            ),
            (
                BuiltInModelCatalog.whisperKitSmall216MB,
                "openai_whisper-small_216MB",
                "openai/whisper-small",
                "Multilingual (~99 languages)",
                nil,
                commonRequiredPaths
            ),
            (
                BuiltInModelCatalog.whisperKitSmallEn217MB,
                "openai_whisper-small.en_217MB",
                "openai/whisper-small.en",
                "English",
                nil,
                commonRequiredPaths
            ),
            (
                BuiltInModelCatalog.whisperKitLargeV3626MB,
                "openai_whisper-large-v3-v20240930_626MB",
                "openai/whisper-large-v3",
                "Multilingual (~99 languages)",
                nil,
                commonRequiredPaths
            ),
            (
                BuiltInModelCatalog.whisperKitLargeV3Turbo632MB,
                "openai_whisper-large-v3-v20240930_turbo_632MB",
                "openai/whisper-large-v3",
                "Multilingual (~99 languages)",
                .m2OrLater,
                [
                    "AudioEncoder.mlmodelc/coremldata.bin",
                    "MelSpectrogram.mlmodelc/coremldata.bin",
                    "TextDecoder.mlmodelc/coremldata.bin",
                    "TextDecoderContextPrefill.mlmodelc/coremldata.bin",
                    "config.json",
                    "generation_config.json",
                    "tokenizer/config.json",
                    "tokenizer/tokenizer.json",
                    "tokenizer/tokenizer_config.json",
                    "tokenizer/vocab.json",
                    "tokenizer/merges.txt",
                    "tokenizer/added_tokens.json",
                    "tokenizer/special_tokens_map.json",
                    "tokenizer/normalizer.json",
                ]
            ),
        ]

        for item in expected {
            XCTAssertEqual(item.descriptor.engine, .whisperKit)
            XCTAssertEqual(item.descriptor.engine.capabilities, [.asr, .streamingASR])
            XCTAssertEqual(item.descriptor.repository, "argmaxinc/whisperkit-coreml")
            XCTAssertEqual(item.descriptor.revision, "main")
            XCTAssertFalse(item.descriptor.shortDescription.isEmpty)
            XCTAssertTrue(item.descriptor.displayName.contains("(WhisperKit"))
            XCTAssertEqual(item.descriptor.repoFolderName, item.repoFolderName)
            XCTAssertEqual(item.descriptor.tokenizerSource, item.tokenizerSource)
            XCTAssertEqual(item.descriptor.madeBy, "OpenAI · Argmax")
            XCTAssertEqual(item.descriptor.worksWith, item.worksWith)
            XCTAssertFalse(item.descriptor.goodFor?.isEmpty ?? true)
            XCTAssertEqual(
                item.descriptor.license,
                "MIT (WhisperKit) + Apache 2.0 (Whisper weights)"
            )
            XCTAssertEqual(item.descriptor.requiredChipFamily, item.requiredChipFamily)
            XCTAssertEqual(item.descriptor.requiredRelativePaths, item.requiredPaths)
        }
    }

    func testWhisperKitDescriptorSizesStayWithinExpectedRanges() {
        let expectedRanges: [(ModelDescriptor, ClosedRange<Int64>)] = [
            (BuiltInModelCatalog.whisperKitTiny, 73_000_000...81_000_000),
            (BuiltInModelCatalog.whisperKitSmall216MB, 205_000_000...227_000_000),
            (BuiltInModelCatalog.whisperKitSmallEn217MB, 206_000_000...228_000_000),
            (BuiltInModelCatalog.whisperKitLargeV3626MB, 595_000_000...657_000_000),
            (BuiltInModelCatalog.whisperKitLargeV3Turbo632MB, 600_000_000...664_000_000),
        ]

        for (descriptor, expectedRange) in expectedRanges {
            XCTAssertTrue(
                expectedRange.contains(descriptor.approximateSizeBytes),
                "\(descriptor.id) expected size \(descriptor.approximateSizeBytes) not in \(expectedRange)"
            )
        }
    }

    func testWhisperCppDescriptorsAreRegisteredAndEnabled() {
        let whisperCppDescriptors = BuiltInModelCatalog.registeredModels
            .filter { $0.engine == .whisperCpp }
        let expectedIDs: Set<String> = [
            BuiltInModelCatalog.whisperCppTiny.id,
            BuiltInModelCatalog.whisperCppSmallQ51.id,
            BuiltInModelCatalog.whisperCppLargeV3TurboQ50.id,
        ]

        XCTAssertEqual(Set(whisperCppDescriptors.map(\.id)), expectedIDs)
        for descriptor in whisperCppDescriptors {
            XCTAssertTrue(
                descriptor.isEnabled,
                "\(descriptor.id) should be live after the Stage B atomic enable"
            )
        }
    }

    func testWhisperCppDescriptorsPinExpectedStageBContract() {
        let expected: [(descriptor: ModelDescriptor, repoFolderName: String, requiredPath: String, approximateSizeBytes: Int64)] = [
            (
                BuiltInModelCatalog.whisperCppTiny,
                "whispercpp-tiny",
                "ggml-tiny.bin",
                77_691_713
            ),
            (
                BuiltInModelCatalog.whisperCppSmallQ51,
                "whispercpp-small-q5_1",
                "ggml-small-q5_1.bin",
                190_085_487
            ),
            (
                BuiltInModelCatalog.whisperCppLargeV3TurboQ50,
                "whispercpp-large-v3-turbo-q5_0",
                "ggml-large-v3-turbo-q5_0.bin",
                574_041_195
            ),
        ]

        for item in expected {
            XCTAssertEqual(item.descriptor.engine, .whisperCpp)
            XCTAssertEqual(item.descriptor.engine.capabilities, [.asr, .streamingASR])
            XCTAssertEqual(item.descriptor.repository, "ggerganov/whisper.cpp")
            XCTAssertEqual(
                item.descriptor.revision,
                "5359861c739e955e79d9a303bcbc70fb988958b1"
            )
            XCTAssertFalse(item.descriptor.shortDescription.isEmpty)
            XCTAssertTrue(item.descriptor.displayName.contains("(whisper.cpp)"))
            XCTAssertEqual(item.descriptor.repoFolderName, item.repoFolderName)
            XCTAssertEqual(item.descriptor.requiredRelativePaths, [item.requiredPath])
            XCTAssertEqual(item.descriptor.approximateSizeBytes, item.approximateSizeBytes)
            XCTAssertNil(item.descriptor.tokenizerSource)
            XCTAssertNil(item.descriptor.requiredChipFamily)
            XCTAssertEqual(item.descriptor.madeBy, "OpenAI · ggml-org")
            XCTAssertEqual(item.descriptor.worksWith, "Multilingual (~99 languages)")
            XCTAssertFalse(item.descriptor.goodFor?.isEmpty ?? true)
            XCTAssertEqual(item.descriptor.license, "MIT")
        }
    }

    func testWhisperFamilyLanguageCodesStayStable() {
        XCTAssertEqual(WhisperFamilyLanguages.codes.count, 100)
        XCTAssertEqual(Set(WhisperFamilyLanguages.codes).count, WhisperFamilyLanguages.codes.count)
        XCTAssertTrue(Set(WhisperFamilyLanguages.codes).isSuperset(of: ["en", "ja", "zh", "es", "de"]))
    }

    func testSupportedLanguagesMatchRev3MultilingualScope() {
        let whisperFamilyDescriptorIDs: Set<String> = [
            BuiltInModelCatalog.whisperKitTiny.id,
            BuiltInModelCatalog.whisperKitSmall216MB.id,
            BuiltInModelCatalog.whisperKitLargeV3626MB.id,
            BuiltInModelCatalog.whisperKitLargeV3Turbo632MB.id,
            BuiltInModelCatalog.whisperCppTiny.id,
            BuiltInModelCatalog.whisperCppSmallQ51.id,
            BuiltInModelCatalog.whisperCppLargeV3TurboQ50.id,
        ]
        let qwen3DescriptorIDs: Set<String> = [
            BuiltInModelCatalog.qwen3AsrF32.id,
            BuiltInModelCatalog.qwen3AsrInt8.id,
        ]

        for descriptor in BuiltInModelCatalog.registeredModels {
            if whisperFamilyDescriptorIDs.contains(descriptor.id) {
                XCTAssertEqual(
                    descriptor.supportedLanguages,
                    WhisperFamilyLanguages.codes,
                    "\(descriptor.id) should expose the shared Whisper-family language list"
                )
            } else if qwen3DescriptorIDs.contains(descriptor.id) {
                XCTAssertEqual(
                    descriptor.supportedLanguages,
                    Qwen3Languages.codes,
                    "\(descriptor.id) should expose the Qwen3 language list"
                )
            } else {
                XCTAssertNil(
                    descriptor.supportedLanguages,
                    "\(descriptor.id) should not expose a v1 language picker"
                )
            }
        }
    }
}
