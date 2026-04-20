import Foundation
import XCTest
@testable import PersonalScribeCore

final class OnboardingStateTests: XCTestCase {
    func testResolveDefaultsToFalseWhenUnset() {
        let defaults = makeDefaults()

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)
        XCTAssertFalse(OnboardingState.resolve(from: defaults).rawValue)
    }

    func testPersistRoundTripStoresBooleanTrue() {
        let defaults = makeDefaults()

        OnboardingState.completed.persist(to: defaults)

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .completed)
        XCTAssertTrue(OnboardingState.resolve(from: defaults).rawValue)
    }

    func testResolveFallsBackToFalseWhenStoredTypeIsInvalid() {
        let defaults = makeDefaults()
        defaults.set("invalid", forKey: OnboardingState.userDefaultsKey)

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)
        XCTAssertFalse(OnboardingState.resolve(from: defaults).rawValue)
    }

    private func makeDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: #function)!
        defaults.removePersistentDomain(forName: #function)
        return defaults
    }
}
