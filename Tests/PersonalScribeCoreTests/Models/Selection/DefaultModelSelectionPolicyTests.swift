import XCTest
@testable import PersonalScribeCore

/// Tests for `DefaultModelSelectionPolicy`. Two branches: below
/// threshold returns lightweight, above returns baseline. Ticket
/// #016.
final class DefaultModelSelectionPolicyTests: XCTestCase {
    func testBelowThresholdReturnsLightweight() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: 8 * 1024 * 1024 * 1024,
            lightweight: BuiltInModelCatalog.parakeetTDTCTC110M,
            baseline: BuiltInModelCatalog.parakeetTDT06Bv2
        )
        XCTAssertEqual(pick.id, BuiltInModelCatalog.parakeetTDTCTC110M.id)
    }

    func testAtOrAboveThresholdReturnsBaseline() {
        let pick = DefaultModelSelectionPolicy.recommendedDefault(
            physicalMemoryBytes: 16 * 1024 * 1024 * 1024,
            lightweight: BuiltInModelCatalog.parakeetTDTCTC110M,
            baseline: BuiltInModelCatalog.parakeetTDT06Bv2
        )
        XCTAssertEqual(pick.id, BuiltInModelCatalog.parakeetTDT06Bv2.id)
    }
}
