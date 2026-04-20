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
        /// Fraction of the canvas half-height used by the peak wave at
        /// `smoothedLevel == 1.0`. Chosen so a 28 pt pill panel
        /// (14 pt half-height) shows a clearly visible ~5.6 pt peak.
        public static let maxAmpFactor: CGFloat = 0.4

        public static func clampedLevel(_ raw: Double) -> Double {
            min(1.0, max(0.0, raw))
        }

        /// Maximum positive/negative stroke offset from the horizontal
        /// midline, given the smoothed audio level and canvas height.
        public static func amplitude(
            for level: Double,
            canvasHeight: CGFloat
        ) -> CGFloat {
            let clamped = clampedLevel(level)
            let peak = canvasHeight * maxAmpFactor
            return peak * CGFloat(clamped)
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
