import XCTest
@testable import SeshatCore

/// Tests for `WaveformDecayMode` and the pure interpolation helper used by
/// `WaveformView` to fade from the last-known audio level to zero when the
/// audio-level stream terminates (BACKLOG P2S1 TODO: "Trailing `0.0` on
/// audioLevelStream() at stop — UI-layer decay in Sprint 2").
///
/// Sprint 2 prompt specifies:
///   `.animated` = 500ms linear interpolation from last-known level to 0,
///   then snap. `.immediate` = snap to 0 on stream termination (current
///   Sprint 1 behaviour).
final class WaveformDecayModeTests: XCTestCase {
    private let suiteName = "SeshatTestsWaveformDecayMode"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    // MARK: - Enum surface

    func testRawValues() {
        XCTAssertEqual(WaveformDecayMode.immediate.rawValue, "immediate")
        XCTAssertEqual(WaveformDecayMode.animated.rawValue, "animated")
    }

    func testDefaultIsImmediate() {
        XCTAssertEqual(WaveformDecayMode.default, .immediate)
    }

    func testUserDefaultsKey() {
        XCTAssertEqual(WaveformDecayMode.userDefaultsKey, "WaveformDecayMode")
    }

    // MARK: - Resolve

    func testResolveReturnsDefaultWhenKeyAbsent() {
        let defaults = isolatedDefaults()
        XCTAssertEqual(WaveformDecayMode.resolve(from: defaults), .immediate)
    }

    func testResolveReturnsDefaultForUnrecognizedValue() {
        let defaults = isolatedDefaults()
        defaults.set("garbage", forKey: WaveformDecayMode.userDefaultsKey)
        XCTAssertEqual(WaveformDecayMode.resolve(from: defaults), .immediate)
    }

    func testPreferenceResolveAnimatedWhenPersisted() {
        let defaults = isolatedDefaults()
        let preference = WaveformDecayMode.preference(defaults: defaults)
        preference.persist(.animated)

        XCTAssertEqual(preference.resolve(), .animated)
        XCTAssertEqual(WaveformDecayMode.resolve(from: defaults), .animated)
    }

    // MARK: - Persist round-trip

    func testPersistRoundTripImmediate() {
        let defaults = isolatedDefaults()
        WaveformDecayMode.preference(defaults: defaults).persist(.immediate)
        XCTAssertEqual(
            defaults.string(forKey: WaveformDecayMode.userDefaultsKey),
            "immediate"
        )
    }

    // MARK: - Duration contract

    func testAnimatedDurationIs500ms() {
        XCTAssertEqual(WaveformDecayMode.animated.durationSeconds, 0.5, accuracy: 0.0001)
    }

    func testImmediateDurationIsZero() {
        XCTAssertEqual(WaveformDecayMode.immediate.durationSeconds, 0.0, accuracy: 0.0001)
    }

    // MARK: - Linear interpolation (pure math, no clock)

    func testLinearDecayAtStartReturnsStartLevel() {
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: 0.0,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.8, accuracy: 0.0001)
    }

    func testLinearDecayAtMidpointIsHalfOfStartLevel() {
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: 0.25,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.4, accuracy: 0.0001)
    }

    func testLinearDecayAtEndReturnsZero() {
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: 0.5,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.0, accuracy: 0.0001)
    }

    func testLinearDecayAfterEndSnapsToZero() {
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: 1.0,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.0, accuracy: 0.0001)
    }

    func testLinearDecayBeforeStartClampsToStartLevel() {
        // Defensive — negative elapsed should not overshoot.
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: -0.1,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.8, accuracy: 0.0001)
    }

    func testLinearDecayWithZeroDurationSnapsImmediately() {
        // For `.immediate` mode, duration = 0 → always 0 (snap).
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.8,
            elapsed: 0.0,
            duration: 0.0
        )
        XCTAssertEqual(level, 0.0, accuracy: 0.0001)
    }

    func testLinearDecayWithZeroStartLevelStaysZero() {
        let level = WaveformDecayMode.linearLevel(
            startLevel: 0.0,
            elapsed: 0.25,
            duration: 0.5
        )
        XCTAssertEqual(level, 0.0, accuracy: 0.0001)
    }
}
