import SwiftUI
import XCTest
@testable import SeshatAppKit

/// Tests for the `WaveformView` audio-level meter.
///
/// Locked-in decision (plan step 2.3, Phase 2 cross-cutting):
/// `TimelineView(.animation)` is enabled ONLY when the `isActive` binding
/// is true. When inactive, the view redraws on-demand keyed to the
/// `audioLevel` binding. This keeps idle-pill CPU cost near zero.
final class WaveformViewTests: XCTestCase {
    func testInitializerAcceptsAudioLevelAndIsActiveBindings() {
        let level: Double = 0.3
        let active: Bool = true
        let view = WaveformView(
            audioLevel: .constant(level),
            isActive: .constant(active)
        )
        XCTAssertEqual(view.currentAudioLevel, 0.3, accuracy: 0.001)
        XCTAssertEqual(view.currentIsActive, true)
    }

    func testDefaultBarCountMatchesSpec() {
        // Waveform asset shows ~32 bars across the pill width.
        XCTAssertEqual(WaveformView.defaultBarCount, 32)
    }

    func testGeometryClampsNegativeAudioLevelToZero() {
        let clamped = WaveformView.Geometry.clampedLevel(-0.3)
        XCTAssertEqual(clamped, 0, accuracy: 0.0001)
    }

    func testGeometryClampsAudioLevelAboveOneToOne() {
        let clamped = WaveformView.Geometry.clampedLevel(1.7)
        XCTAssertEqual(clamped, 1, accuracy: 0.0001)
    }

    func testGeometryBarHeightScalesWithAudioLevel() {
        let availableHeight: CGFloat = 30
        let atZero = WaveformView.Geometry.barHeight(
            barIndex: 16,
            totalBars: 32,
            level: 0.0,
            phase: 0.0,
            availableHeight: availableHeight
        )
        let atFull = WaveformView.Geometry.barHeight(
            barIndex: 16,
            totalBars: 32,
            level: 1.0,
            phase: 0.0,
            availableHeight: availableHeight
        )
        XCTAssertLessThan(atZero, atFull)
        XCTAssertGreaterThan(atZero, 0, "minimum bar height must be non-zero for idle look")
        XCTAssertLessThanOrEqual(atFull, availableHeight)
    }

    func testGeometryActivePhaseDrivesDifferentHeightsAcrossBars() {
        let availableHeight: CGFloat = 30
        let h0 = WaveformView.Geometry.barHeight(
            barIndex: 0,
            totalBars: 32,
            level: 0.6,
            phase: 0.0,
            availableHeight: availableHeight
        )
        let h1 = WaveformView.Geometry.barHeight(
            barIndex: 1,
            totalBars: 32,
            level: 0.6,
            phase: 0.0,
            availableHeight: availableHeight
        )
        XCTAssertNotEqual(h0, h1, "bars must differ to form a waveform silhouette")
    }

    func testGeometryIdleLevelProducesFlatProfile() {
        // When audioLevel == 0 and inactive, the idle profile should be a
        // low flat line (non-zero but not varying dramatically).
        let availableHeight: CGFloat = 30
        let heights = (0..<32).map { idx in
            WaveformView.Geometry.barHeight(
                barIndex: idx,
                totalBars: 32,
                level: 0.0,
                phase: 0.0,
                availableHeight: availableHeight
            )
        }
        let max = heights.max() ?? 0
        let min = heights.min() ?? 0
        XCTAssertLessThanOrEqual(
            max - min,
            availableHeight * 0.2,
            "idle profile should be roughly flat"
        )
    }
}
