import XCTest
@testable import SeshatCore

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
}
