import XCTest
@testable import PersonalScribeCore

final class LegacyWorkflowModeTests: XCTestCase {
    func testDefaultRegistryContainsDictation() {
        XCTAssertEqual(ModeRegistry.all, [ModeRegistry.dictation])
        XCTAssertEqual(ModeRegistry.dictation.name, "Dictation")
        XCTAssertEqual(ModeRegistry.dictation.voiceModelID, BuiltInModelCatalog.defaultModelId)
    }

    func testLookupByIDReturnsRegisteredDescriptor() {
        XCTAssertEqual(ModeRegistry.descriptor(for: ModeRegistry.defaultModeID), ModeRegistry.dictation)
    }

    func testUnknownIDReturnsNil() {
        XCTAssertNil(ModeRegistry.descriptor(for: "missing"))
    }
}
