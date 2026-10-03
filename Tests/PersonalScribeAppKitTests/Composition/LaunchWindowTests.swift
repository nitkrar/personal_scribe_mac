import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class LaunchWindowTests: XCTestCase {
    func testLaunchOpensHomeOnceOnboardingIsComplete() {
        XCTAssertEqual(PersonalScribeAppMain.launchTab(isOnboardingComplete: true), .home)
    }

    func testLaunchOpensSettingsWhileOnboardingIsIncomplete() {
        XCTAssertEqual(PersonalScribeAppMain.launchTab(isOnboardingComplete: false), .settings)
    }
}
