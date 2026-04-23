import SwiftUI
import PersonalScribeCore

/// Voice-modulated sine-wave SwiftUI view for the pill overlay's
/// recording state. Phase animates procedurally via
/// `TimelineView(.animation)`; amplitude tracks the live microphone
/// level and linearly decays toward `0` when input goes silent so the
/// wave flattens to a single horizontal line on silence.
///
/// Reference: WisprFlow-style pill spec (2026-04-18 dogfood rewrite);
/// M4.1 re-introduces audio-level modulation on top of that procedural
/// phase. The earlier source comment that claimed an audio-level
/// approach was "jittery at low signal levels" was stale — the real
/// problem was *abrupt per-sample transitions*, which the shared
/// `WaveformDecayMode.animated` 500 ms linear interp already solves
/// (see `WaveformView`). Same pattern is reused here.
///
/// ## Parameters
/// * `audioLevel` — normalized mic level, `0.0` (silent) to `1.0`
///   (max). Clamped internally; values outside the range do not crash.
/// * `decayMode` — how abruptly the amplitude can jump between samples.
///   Under `.immediate`, the wave snaps to the target each frame.
///   Under `.animated` (0.5 s), amplitude linearly interpolates from
///   the previously observed level toward the current target, matching
///   `WaveformView`'s smoothing shape. Default `.animated` keeps the
///   pill's recording wave visually continuous even when the mic RMS
///   stream is jumpy.
/// * `tint` — stroke color.
///
/// ## Rendering
/// `TimelineView(.animation(minimumInterval: 1/30))` always drives the
/// canvas while the view is mounted — phase scrolls continuously
/// whether or not the wave is visible. The pill overlay hides this
/// entire panel when not recording, so the view only exists while
/// recording; no separate `isAnimating` flag is needed.
///
/// Amplitude is derived from a smoothed audio level (see
/// `smoothedLevel(target:last:elapsed:duration:)`) scaled to a maximum
/// of `canvasHeight * Geometry.maxAmpFactor`. At `smoothedLevel == 0`
/// amplitude is `0` and the wave collapses to a flat horizontal line;
/// phase continues to animate but is invisible on the flat line.
@MainActor
public struct SineWaveView: View {
    public let audioLevel: Double
    public let decayMode: WaveformDecayMode
    public let tint: Color

    static let loopPeriod: Double = 1.2

    // Smoothing state — the level we're interpolating *from* and the
    // wall-clock anchor for the in-flight interpolation. Every new
    // distinct `audioLevel` target resets the anchor.
    @State private var lastLevel: Double = 0.0
    @State private var interpStart: Date = .distantPast
    @State private var interpStartLevel: Double = 0.0
    @State private var lastTarget: Double = 0.0

    public init(
        audioLevel: Double,
        decayMode: WaveformDecayMode = .animated,
        tint: Color
    ) {
        self.audioLevel = audioLevel
        self.decayMode = decayMode
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let target = Geometry.clampedLevel(audioLevel)
            let elapsed = context.date.timeIntervalSince(interpStart)
            let smoothed = Geometry.smoothedLevel(
                target: target,
                startLevel: interpStartLevel,
                lastLevel: lastLevel,
                elapsed: elapsed,
                duration: decayMode.durationSeconds
            )
            waveCanvas(
                phase: Self.phase(for: context.date),
                smoothedLevel: smoothed
            )
        }
        .onChange(of: audioLevel) { _, newTarget in
            let clampedNew = Geometry.clampedLevel(newTarget)
            guard clampedNew != Geometry.clampedLevel(lastTarget) else { return }
            // Snapshot where we are right now; smoothing will interp from
            // here toward the new target over `decayMode.durationSeconds`.
            let elapsed = Date().timeIntervalSince(interpStart)
            let currentSmoothed = Geometry.smoothedLevel(
                target: Geometry.clampedLevel(lastTarget),
                startLevel: interpStartLevel,
                lastLevel: lastLevel,
                elapsed: elapsed,
                duration: decayMode.durationSeconds
            )
            interpStartLevel = currentSmoothed
            lastLevel = currentSmoothed
            interpStart = Date()
            lastTarget = clampedNew
        }
    }

    @ViewBuilder
    private func waveCanvas(phase: Double, smoothedLevel: Double) -> some View {
        Canvas { context, size in
            let w = size.width
            let h = size.height
            let amplitude = Geometry.amplitude(
                for: smoothedLevel,
                canvasHeight: h
            )
            let frequency: CGFloat = 2.5

            var path = Path()
            path.move(to: CGPoint(x: 0, y: h / 2))
            var x: CGFloat = 0
            while x <= w {
                let normalized = Double(x / w)
                let angle: Double = normalized * Double(frequency) * 2 * .pi + phase
                let y = h / 2 + amplitude * CGFloat(sin(angle))
                path.addLine(to: CGPoint(x: x, y: y))
                x += 1
            }

            context.stroke(
                path,
                with: .color(tint),
                style: StrokeStyle(
                    lineWidth: 1.5,
                    lineCap: .round,
                    lineJoin: .round
                )
            )
        }
    }

    private static func phase(for date: Date) -> Double {
        let t = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: loopPeriod)
        return (t / loopPeriod) * 2 * .pi
    }

    // MARK: - Geometry helpers

    /// Pure functions that drive amplitude + smoothing. Moved to a
    /// nested `enum` so tests can verify behaviour without rendering
    /// SwiftUI or waiting on real wall-clock time.
    public enum Geometry {
        /// Fraction of the canvas height used by the peak wave offset from
        /// the midline at `smoothedLevel == 1.0`. On a 28 pt pill panel
        /// this yields a 14 pt peak offset — the wave fills the full
        /// canvas at max level (stroke midline to top/bottom edge).
        public static let maxAmpFactor: CGFloat = 0.5

        public static func clampedLevel(_ raw: Double) -> Double {
            min(1.0, max(0.0, raw))
        }

        /// Maximum positive/negative stroke offset from the horizontal
        /// midline, given the smoothed audio level and canvas height.
        ///
        /// ## Amplitude curve — Option A (square root)
        ///
        /// Applies `sqrt(level)` before scaling to the canvas so typical
        /// conversational RMS (0.05-0.15 on a MacBook built-in mic)
        /// produces visible modulation instead of sub-pixel amplitude.
        /// Endpoints are preserved: `level = 0 → 0`, `level = 1 → peak`.
        ///
        /// Example (canvasHeight = 28, maxAmpFactor = 0.5 → peak = 14.0pt):
        ///
        /// | RMS    | sqrt × 0.4 (prior) | sqrt × 0.5 (current) |
        /// | ------ | ------------------ | -------------------- |
        /// | 0.05   | 2.50pt             | 3.13pt               |
        /// | 0.10   | 3.54pt             | 4.43pt               |
        /// | 0.30   | 6.13pt             | 7.67pt               |
        /// | 0.60   | 8.67pt             | 10.84pt              |
        /// | 1.00   | 11.20pt            | 14.00pt              |
        ///
        /// ## Alternatives considered (kept here for rollback / tuning)
        ///
        /// **Option B — Tunable power curve** (`pow(level, exponent)`).
        /// An exponent of ~0.4 lifts low levels slightly more aggressively
        /// than sqrt (exponent 0.5). At RMS 0.10, `pow(0.10, 0.4) ≈ 0.398`
        /// → amp ≈ 4.46pt. One-constant knob if sqrt turns out to be
        /// either too subtle or too dramatic at extremes. Example:
        /// ```swift
        /// let curved = pow(clampedLevel(level), 0.4)
        /// return canvasHeight * maxAmpFactor * CGFloat(curved)
        /// ```
        ///
        /// **Option C — Bump `maxAmpFactor` alone** (e.g. 0.4 → 0.8) while
        /// keeping the linear mapping. Doubles amplitude everywhere but
        /// still leaves typical speech barely visible (RMS 0.10 → 2.24pt)
        /// because the underlying problem is the linear map's
        /// compression of low RMS values, not the peak amplitude cap.
        /// Rejected on its own; could compose with A if the sqrt peak
        /// ever feels too small (unlikely — sqrt already spans 0-11.2pt).
        ///
        /// **Option D — A + bump `maxAmpFactor` to 0.45** for the most
        /// dramatic modulation. At RMS 0.10: ~3.98pt; at RMS 1.0: ~12.6pt
        /// (the outer `min(availableHeight, …)` guard in the caller
        /// already clamps overflow). Hold in reserve if Option A doesn't
        /// feel punchy enough on the build laptop.
        ///
        /// **Rejected alternatives:** log10-scaled perceptual curve
        /// (over-engineered for this UI; sqrt already tracks loudness
        /// perception closely enough), and per-frame auto-gain from a
        /// running RMS max (adds state, fights the silence floor).
        public static func amplitude(
            for level: Double,
            canvasHeight: CGFloat
        ) -> CGFloat {
            let clamped = clampedLevel(level)
            // Option A: sqrt curve. See block comment above for the
            // alternatives and why this one was chosen.
            let curved = clamped.squareRoot()
            let peak = canvasHeight * maxAmpFactor
            return peak * CGFloat(curved)
        }

        /// Linearly interpolate from `startLevel` toward `target` over
        /// `duration` seconds. Behaviour:
        ///
        /// * `duration == 0` — snap to `target` (matches the
        ///   `.immediate` decay contract).
        /// * `0 <= elapsed < duration` — linear lerp.
        /// * `elapsed >= duration` — clamps to `target`.
        ///
        /// `lastLevel` is returned verbatim when `elapsed < 0` (a
        /// guard for clock drift / distantPast anchors before the
        /// first real input).
        public static func smoothedLevel(
            target: Double,
            startLevel: Double,
            lastLevel: Double,
            elapsed: Double,
            duration: Double
        ) -> Double {
            let clampedTarget = clampedLevel(target)
            guard elapsed >= 0 else { return clampedLevel(lastLevel) }
            guard duration > 0 else { return clampedTarget }
            if elapsed >= duration { return clampedTarget }
            let fraction = elapsed / duration
            let interpolated = startLevel + (clampedTarget - startLevel) * fraction
            return clampedLevel(interpolated)
        }
    }
}

#Preview("SineWaveView — low level (0.1)") {
    SineWaveView(
        audioLevel: 0.1,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("SineWaveView — mid level (0.5)") {
    SineWaveView(
        audioLevel: 0.5,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("SineWaveView — high level (0.9)") {
    SineWaveView(
        audioLevel: 0.9,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("SineWaveView — silent (0.0, flat line)") {
    SineWaveView(
        audioLevel: 0.0,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}
