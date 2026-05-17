import XCTest
@testable import PersonalScribeCore

final class ChipFamilyTests: XCTestCase {
    func testCurrentReturnsKnownChipFamily() {
        let current = ChipFamily.current()

        XCTAssertTrue(ChipFamily.allCases.contains(current))
    }

    func testBrandStringAppleM1MapsToM1() {
        XCTAssertEqual(ChipFamily.detect(from: "Apple M1"), .m1)
    }

    func testBrandStringAppleM1ProMapsToM1() {
        XCTAssertEqual(ChipFamily.detect(from: "Apple M1 Pro"), .m1)
    }

    func testBrandStringAppleM2MapsToM2OrLater() {
        XCTAssertEqual(ChipFamily.detect(from: "Apple M2"), .m2OrLater)
    }

    func testBrandStringAppleM3MaxMapsToM2OrLater() {
        XCTAssertEqual(ChipFamily.detect(from: "Apple M3 Max"), .m2OrLater)
    }

    func testBrandStringAppleM4MapsToM2OrLater() {
        XCTAssertEqual(ChipFamily.detect(from: "Apple M4"), .m2OrLater)
    }
}
