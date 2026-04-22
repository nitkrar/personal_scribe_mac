import XCTest
@testable import PersonalScribeCore

final class BuiltInModelCatalogTests: XCTestCase {
    func testRegisteredModelsContainV2V3And110MDescriptors() {
        XCTAssertEqual(
            BuiltInModelCatalog.registeredModels.map(\.id),
            [
                BuiltInModelCatalog.parakeetTDT06Bv2.id,
                BuiltInModelCatalog.parakeetTDTCTC110M.id,
                BuiltInModelCatalog.parakeetTDT06Bv3.id,
            ]
        )
        XCTAssertEqual(
            BuiltInModelCatalog.descriptor(for: BuiltInModelCatalog.parakeetTDT06Bv3.id),
            BuiltInModelCatalog.parakeetTDT06Bv3
        )
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

    func testDefaultActiveDescriptorFallsBackToPinnedV2Descriptor() {
        XCTAssertEqual(
            BuiltInModelCatalog.defaultActiveDescriptor.voiceModel,
            BuiltInModelCatalog.parakeetTDT06Bv2
        )
        XCTAssertNil(BuiltInModelCatalog.defaultActiveDescriptor.aiModelID)
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

    /// Every registered model must carry averageWER + rtfx so the
    /// computed-relative presenter can rank models without nil-fallback
    /// branches. Sourced from the HF Open ASR leaderboard — see the
    /// per-descriptor citation in `BuiltInModelCatalog.swift`.
    func testAllRegisteredModelsCarryPublishedBenchmarks() {
        for descriptor in BuiltInModelCatalog.registeredModels {
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
