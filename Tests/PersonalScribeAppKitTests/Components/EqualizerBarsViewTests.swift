import XCTest
@testable import PersonalScribeAppKit

/// Tests for `EqualizerBarsView.Geometry`. SwiftUI's render + TimelineView
/// animation can't be asserted in XCTest, but the pure bar-geometry
/// helpers that feed the canvas can.
///
/// Contract:
/// * `audioLevel == 0` → bars settle at the minimum-height floor, not
///   flat. Keeps the hold-to-record state visually distinct from idle.
/// * `audioLevel == 1.0` → bar heights reach up to `availableHeight`.
/// * Heights are clamped to `[availableHeight * minHeightFactor,
///   availableHeight]`.
/// * `sqrt` perceptual curve means conversational RMS (0.1) produces
///   visible above-minimum movement.
final class EqualizerBarsViewTests: XCTestCase {
    func testSilentLevelProducesMinimumHeightBars() {
        let canvasHeight: CGFloat = 24
        let minExpected = canvasHeight * EqualizerBarsView.Geometry.minHeightFactor

        for index in 0..<7 {
            let h = EqualizerBarsView.Geometry.barHeight(
                barIndex: index,
                totalBars: 7,
                level: 0.0,
                phase: 0.0,
                availableHeight: canvasHeight
            )
            XCTAssertEqual(
                h,
                minExpected,
                accuracy: 0.0001,
                "Bar \(index) at silence must sit at the minimum floor, not collapse flat"
            )
        }
    }

    func testMaxLevelProducesBarsWithinCanvas() {
        let canvasHeight: CGFloat = 24

        for index in 0..<7 {
            let h = EqualizerBarsView.Geometry.barHeight(
                barIndex: index,
                totalBars: 7,
                level: 1.0,
                phase: 0.0,
                availableHeight: canvasHeight
            )
            XCTAssertGreaterThanOrEqual(h, canvasHeight * 0.5)
            XCTAssertLessThanOrEqual(h, canvasHeight)
        }
    }

    /// Typical MacBook built-in mic RMS for conversational speech sits
    /// around 0.05–0.15. Thanks to the sqrt curve, those levels must
    /// produce bar heights strictly above the silent-floor minimum on a
    /// 24pt canvas (regression guard: the pill must look "alive").
    func testConversationalLevelLiftsBarsAboveMinimum() {
        let canvasHeight: CGFloat = 24
        let minExpected = canvasHeight * EqualizerBarsView.Geometry.minHeightFactor

        for index in 0..<7 {
            let h = EqualizerBarsView.Geometry.barHeight(
                barIndex: index,
                totalBars: 7,
                level: 0.10,
                phase: 1.0,       // non-zero phase so shimmer kicks in
                availableHeight: canvasHeight
            )
            XCTAssertGreaterThan(
                h,
                minExpected,
                "Bar \(index) at RMS 0.10 must lift above the silent floor"
            )
        }
    }

    func testBarHeightsClampedToCanvasBounds() {
        let canvasHeight: CGFloat = 24

        // Try a grid of phases + levels and confirm every result stays
        // inside the [minHeightFactor * canvasHeight, canvasHeight]
        // envelope.
        for level in stride(from: 0.0, through: 1.0, by: 0.1) {
            for phase in stride(from: 0.0, through: 2.0, by: 0.25) {
                for index in 0..<7 {
                    let h = EqualizerBarsView.Geometry.barHeight(
                        barIndex: index,
                        totalBars: 7,
                        level: level,
                        phase: phase,
                        availableHeight: canvasHeight
                    )
                    XCTAssertGreaterThanOrEqual(
                        h,
                        canvasHeight * EqualizerBarsView.Geometry.minHeightFactor - 0.0001
                    )
                    XCTAssertLessThanOrEqual(h, canvasHeight + 0.0001)
                }
            }
        }
    }

    func testZeroCanvasHeightReturnsZero() {
        XCTAssertEqual(
            EqualizerBarsView.Geometry.barHeight(
                barIndex: 3,
                totalBars: 7,
                level: 1.0,
                phase: 0.0,
                availableHeight: 0
            ),
            0,
            accuracy: 0.0001
        )
    }

    func testClampsLevelToValidRange() {
        XCTAssertEqual(EqualizerBarsView.Geometry.clampedLevel(1.5), 1.0, accuracy: 0.0001)
        XCTAssertEqual(EqualizerBarsView.Geometry.clampedLevel(-0.3), 0.0, accuracy: 0.0001)
        XCTAssertEqual(EqualizerBarsView.Geometry.clampedLevel(0.5), 0.5, accuracy: 0.0001)
    }
}
