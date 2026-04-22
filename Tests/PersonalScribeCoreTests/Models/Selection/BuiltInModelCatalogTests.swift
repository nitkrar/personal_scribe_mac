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

    /// Every registered model must carry speed + accuracy ratings so
    /// the info popover can render its visual bars without nil-fallback
    /// branches.
    func testAllRegisteredModelsCarrySpeedAndAccuracyRatings() {
        for descriptor in BuiltInModelCatalog.registeredModels {
            XCTAssertNotNil(
                descriptor.speedRating,
                "\(descriptor.id) missing speedRating"
            )
            XCTAssertNotNil(
                descriptor.accuracyRating,
                "\(descriptor.id) missing accuracyRating"
            )
        }
    }

    /// CTC-110M is meaningfully faster than the 0.6B variants and has
    /// noticeably lower accuracy. Pin this so a future careless rating
    /// edit can't flatten the axis that justifies the model's
    /// existence.
    func test110MIsRatedFasterAndLessAccurateThan06BV2() {
        let light = BuiltInModelCatalog.parakeetTDTCTC110M
        let standard = BuiltInModelCatalog.parakeetTDT06Bv2

        XCTAssertGreaterThan(
            light.speedRating!.rank,
            standard.speedRating!.rank,
            "CTC-110M should outrank 0.6B v2 on speed"
        )
        XCTAssertLessThan(
            light.accuracyRating!.rank,
            standard.accuracyRating!.rank,
            "CTC-110M should rank lower than 0.6B v2 on accuracy"
        )
    }
}
