import XCTest
@testable import PersonalScribeCore

final class BuiltInModelCatalogTests: XCTestCase {
    func testRegisteredModelsContainExpectedASRAndPlaceholderDescriptors() {
        // Refactor #024.10: the catalog now ships 9 descriptors across
        // 4 kinds. ASR rows surface in the AI Models tab today;
        // streaming / qwen3 / diarization rows are placeholders for
        // future adapters (#078).
        XCTAssertEqual(
            BuiltInModelCatalog.registeredModels.map(\.id),
            [
                BuiltInModelCatalog.parakeetTDT06Bv2.id,
                BuiltInModelCatalog.parakeetTDTCTC110M.id,
                BuiltInModelCatalog.parakeetTDT06Bv3.id,
                BuiltInModelCatalog.parakeetEou160ms.id,
                BuiltInModelCatalog.parakeetEou320ms.id,
                BuiltInModelCatalog.parakeetEou1280ms.id,
                BuiltInModelCatalog.qwen3AsrF32.id,
                BuiltInModelCatalog.qwen3AsrInt8.id,
                BuiltInModelCatalog.speakerDiarization.id,
            ]
        )
    }

    func testQwenDescriptorsAreDisabledInRegistry() {
        XCTAssertFalse(BuiltInModelCatalog.qwen3AsrF32.isEnabled)
        XCTAssertFalse(BuiltInModelCatalog.qwen3AsrInt8.isEnabled)
    }

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
        // registry but is disabled for now, and it still ships without
        // the benchmark metadata this popover ranking consumes.
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
}
