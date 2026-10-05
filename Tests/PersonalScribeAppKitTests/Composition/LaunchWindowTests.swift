import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class LaunchWindowTests: XCTestCase {
    func testLaunchSkipsSetupOnceOnboardingIsComplete() {
        XCTAssertFalse(PersonalScribeAppMain.shouldOpenSetupAtLaunch(isOnboardingComplete: true))
    }

    func testLaunchOpensSetupWhileOnboardingIsIncomplete() {
        XCTAssertTrue(PersonalScribeAppMain.shouldOpenSetupAtLaunch(isOnboardingComplete: false))
    }
}
