import XCTest
@testable import PersonalScribeCore

final class ModelDescriptorTests: XCTestCase {
    func testLegacyBuiltInDescriptorsDefaultTokenizerSourceAndRequiredChipFamilyToNil() {
        let legacyDescriptors = BuiltInModelCatalog.registeredModels.filter { $0.engine != .whisperKit }

        XCTAssertFalse(legacyDescriptors.isEmpty)
        for descriptor in legacyDescriptors {
            XCTAssertNil(
                descriptor.tokenizerSource,
                "\(descriptor.id) unexpectedly sets tokenizerSource outside the WhisperKit catalog rows"
            )
            XCTAssertNil(
                descriptor.requiredChipFamily,
                "\(descriptor.id) unexpectedly sets requiredChipFamily outside the WhisperKit catalog rows"
            )
        }
    }
}
