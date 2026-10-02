import XCTest
@testable import PersonalScribeCore

final class CancelCardDurationTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let name = "PersonalScribeTestsCancelCardDuration"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    func testDefaultsToThreeSeconds() {
        XCTAssertEqual(CancelCardDuration.resolve(from: isolatedDefaults()).seconds, 3.0)
    }

    func testPersistedValueRoundTripsAndIsClamped() {
        let defaults = isolatedDefaults()
        CancelCardDuration.persist(to: defaults, .init(seconds: 6))
        XCTAssertEqual(CancelCardDuration.resolve(from: defaults).seconds, 6)

        CancelCardDuration.persist(to: defaults, .init(seconds: 60))
        XCTAssertEqual(CancelCardDuration.resolve(from: defaults).seconds, CancelCardDuration.maximumSeconds)
    }
}
