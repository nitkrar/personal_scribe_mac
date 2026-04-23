import XCTest

@testable import PersonalScribeCore

final class VadPreferencesTests: XCTestCase {

    func testInitClampsBelowFloor() {
        let prefs = VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 0.25)
        XCTAssertEqual(
            prefs.silenceThresholdSeconds,
            VadPreferences.minSilenceThresholdSeconds,
            "below-floor thresholds must clamp to the minimum"
        )
    }

    func testInitClampsAboveCeiling() {
        let prefs = VadPreferences(autoStopEnabled: true, silenceThresholdSeconds: 30)
        XCTAssertEqual(
            prefs.silenceThresholdSeconds,
            VadPreferences.maxSilenceThresholdSeconds,
            "above-ceiling thresholds must clamp to the maximum"
        )
    }
}
