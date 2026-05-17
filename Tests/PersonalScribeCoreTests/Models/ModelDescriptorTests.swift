import XCTest
@testable import PersonalScribeCore

final class ModelDescriptorTests: XCTestCase {
    func testExistingBuiltInDescriptorsDefaultTokenizerSourceAndRequiredChipFamilyToNil() {
        for descriptor in BuiltInModelCatalog.registeredModels {
            XCTAssertNil(
                descriptor.tokenizerSource,
                "\(descriptor.id) unexpectedly sets tokenizerSource before #095 A.5"
            )
            XCTAssertNil(
                descriptor.requiredChipFamily,
                "\(descriptor.id) unexpectedly sets requiredChipFamily before #095 A.5"
            )
        }
    }
}
