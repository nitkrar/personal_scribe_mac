import XCTest
@testable import SeshatCore

final class ModeDescriptorTests: XCTestCase {
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
