import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for `AudioPlayerThumbnail` — a compact audio-player surface
/// showing duration + a static waveform pose. Consumed by the Notes
/// Context Panel (Phase 3).
@MainActor
final class AudioPlayerThumbnailTests: XCTestCase {
    // MARK: - Initializer / stored state

    func testInitializerStoresDurationAndLevelPose() {
        let t = AudioPlayerThumbnail(durationSeconds: 42, levelPose: 0.5)
        XCTAssertEqual(t.durationSeconds, 42, accuracy: 0.001)
        XCTAssertEqual(t.levelPose, 0.5, accuracy: 0.001)
    }

    func testDefaultLevelPoseIsDefined() {
        let t = AudioPlayerThumbnail(durationSeconds: 10)
        // Default is a visually-balanced mid-low pose; lock in the value.
        XCTAssertEqual(t.levelPose, 0.35, accuracy: 0.001)
    }

    // MARK: - Duration formatting

    func testDurationFormatsZeroSeconds() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(0),
            "0:00"
        )
    }

    func testDurationFormatsUnderOneMinute() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(9),
            "0:09"
        )
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(59),
            "0:59"
        )
    }

    func testDurationFormatsMinutesAndSeconds() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(75),
            "1:15"
        )
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(600),
            "10:00"
        )
    }

    func testDurationFormatsHoursMinutesSeconds() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(3_725),
            "1:02:05"
        )
    }

    func testDurationRoundsFractionalSeconds() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(59.6),
            "1:00"
        )
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(59.4),
            "0:59"
        )
    }

    func testDurationNegativeInputTreatedAsZero() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(-120),
            "0:00"
        )
    }

    func testDurationNonFiniteFallsBackToZero() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(.infinity),
            "0:00"
        )
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.formatDuration(.nan),
            "0:00"
        )
    }

    func testDurationLabelPropertyReflectsFormatter() {
        let t = AudioPlayerThumbnail(durationSeconds: 125)
        XCTAssertEqual(t.durationLabel, "2:05")
    }

    // MARK: - Level clamping

    func testLevelClampInRangeIsPassthrough() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.clampLevel(0.4),
            0.4,
            accuracy: 0.0001
        )
    }

    func testLevelClampNegativeBecomesZero() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.clampLevel(-1.5),
            0,
            accuracy: 0.0001
        )
    }

    func testLevelClampAboveOneBecomesOne() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.clampLevel(2.3),
            1.0,
            accuracy: 0.0001
        )
    }

    func testLevelClampNaNFallsBackToZero() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.clampLevel(.nan),
            0,
            accuracy: 0.0001
        )
    }

    func testLevelClampInfinityFallsBackToZero() {
        XCTAssertEqual(
            AudioPlayerThumbnail.Formatters.clampLevel(.infinity),
            0,
            accuracy: 0.0001
        )
    }

    func testClampedLevelPropertyReflectsFormatter() {
        let t = AudioPlayerThumbnail(durationSeconds: 1, levelPose: 2.0)
        XCTAssertEqual(t.clampedLevel, 1.0, accuracy: 0.0001)

        let t2 = AudioPlayerThumbnail(durationSeconds: 1, levelPose: -0.2)
        XCTAssertEqual(t2.clampedLevel, 0.0, accuracy: 0.0001)
    }
}
