import SwiftUI
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `SineWaveView` — the pill overlay's voice-modulated
/// recording wave. The actual Canvas drawing can't be XCTest'd, but
/// the pure geometry + smoothing helpers that feed the canvas can.
///
/// Contract under test (M4.1):
///
/// * `audioLevel == 0` → amplitude `0` (flat horizontal line).
/// * `audioLevel == 1.0` → maximum amplitude for the canvas height.
/// * Intermediate levels scale linearly.
/// * Input is clamped to `[0, 1]`; out-of-range values are tolerated.
/// * `.animated` decay linearly interpolates level across its
///   `durationSeconds` window; intermediate samples are strictly
///   between `startLevel` and `target`.
@MainActor
final class SineWaveViewTests: XCTestCase {

    // MARK: - Amplitude helpers

    func testZeroAudioLevelProducesFlatWave() {
        let amp = SineWaveView.Geometry.amplitude(
            for: 0.0,
            canvasHeight: 28
        )
        XCTAssertEqual(
            amp,
            0,
            accuracy: 0.0001,
            "Silence must collapse the wave to a flat horizontal line."
        )
    }

    func testMaxAudioLevelProducesVisibleWave() {
        let canvasHeight: CGFloat = 28
        let amp = SineWaveView.Geometry.amplitude(
            for: 1.0,
            canvasHeight: canvasHeight
        )
        XCTAssertGreaterThan(amp, 0)
        XCTAssertLessThanOrEqual(amp, canvasHeight / 2)
        XCTAssertEqual(
            amp,
            canvasHeight * SineWaveView.Geometry.maxAmpFactor,
            accuracy: 0.0001
        )
    }

    func testAudioLevelScalesAmplitude() {
        let canvasHeight: CGFloat = 28
        let half = SineWaveView.Geometry.amplitude(
            for: 0.5,
            canvasHeight: canvasHeight
        )
        let full = SineWaveView.Geometry.amplitude(
            for: 1.0,
            canvasHeight: canvasHeight
        )
        // Linear scaling: amplitude(0.5) ≙ 0.5 * amplitude(1.0).
        XCTAssertEqual(half, full * 0.5, accuracy: 0.0001)
    }

    // MARK: - Clamping

    func testClampsAudioLevelAboveOneToOne() {
        XCTAssertEqual(
            SineWaveView.Geometry.clampedLevel(1.7),
            1.0,
            accuracy: 0.0001
        )
        // Amplitude at out-of-range high value must equal amplitude at 1.0.
        let ampOver = SineWaveView.Geometry.amplitude(
            for: 2.5,
            canvasHeight: 28
        )
        let ampOne = SineWaveView.Geometry.amplitude(
            for: 1.0,
            canvasHeight: 28
        )
        XCTAssertEqual(ampOver, ampOne, accuracy: 0.0001)
    }

    func testClampsNegativeAudioLevelToZero() {
        XCTAssertEqual(
            SineWaveView.Geometry.clampedLevel(-0.3),
            0.0,
            accuracy: 0.0001
        )
        let ampNeg = SineWaveView.Geometry.amplitude(
            for: -1.0,
            canvasHeight: 28
        )
        XCTAssertEqual(ampNeg, 0, accuracy: 0.0001)
    }

    // MARK: - Smoothing / decay

    func testAnimatedDecaySmoothsTransitionFromZeroToOne() {
        let duration = WaveformDecayMode.animated.durationSeconds
        // Step from silence (0.0) to full (1.0). At elapsed = duration/2
        // the smoothed level must be strictly between 0 and 1, close to
        // the midpoint.
        let mid = SineWaveView.Geometry.smoothedLevel(
            target: 1.0,
            startLevel: 0.0,
            lastLevel: 0.0,
            elapsed: duration / 2.0,
            duration: duration
        )
        XCTAssertGreaterThan(mid, 0.0)
        XCTAssertLessThan(mid, 1.0)
        XCTAssertEqual(mid, 0.5, accuracy: 0.05)
    }

    func testAnimatedDecayClampsToTargetAfterDuration() {
        let duration = WaveformDecayMode.animated.durationSeconds
        let afterWindow = SineWaveView.Geometry.smoothedLevel(
            target: 1.0,
            startLevel: 0.0,
            lastLevel: 0.0,
            elapsed: duration + 0.25,
            duration: duration
        )
        XCTAssertEqual(afterWindow, 1.0, accuracy: 0.0001)
    }

    func testImmediateDecaySnapsToTarget() {
        let immediate = WaveformDecayMode.immediate.durationSeconds
        let smoothed = SineWaveView.Geometry.smoothedLevel(
            target: 0.8,
            startLevel: 0.1,
            lastLevel: 0.1,
            elapsed: 0.001,
            duration: immediate
        )
        XCTAssertEqual(smoothed, 0.8, accuracy: 0.0001)
    }

    func testAnimatedDecaySmoothsFromSpeechToSilence() {
        // Inverse direction — speech (1.0) to silence (0.0). Mid-window
        // must be strictly between 0 and 1.
        let duration = WaveformDecayMode.animated.durationSeconds
        let mid = SineWaveView.Geometry.smoothedLevel(
            target: 0.0,
            startLevel: 1.0,
            lastLevel: 1.0,
            elapsed: duration / 2.0,
            duration: duration
        )
        XCTAssertGreaterThan(mid, 0.0)
        XCTAssertLessThan(mid, 1.0)
        XCTAssertEqual(mid, 0.5, accuracy: 0.05)
    }

    // MARK: - Default wiring

    func testDefaultDecayModeIsAnimated() {
        // Callers using the pill get 500 ms smoothing out of the box —
        // the whole point of M4.1 is hiding mic-RMS jitter.
        let view = SineWaveView(
            audioLevel: 0.3,
            tint: .white
        )
        XCTAssertEqual(view.decayMode, .animated)
    }
}
