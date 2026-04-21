import SwiftUI

/// 7-bar vertical equaliser used by the pill's hold-to-record state
/// (pill UX spec §2b, §4).
///
/// Bar heights animate at ~30 fps via `TimelineView(.animation)`, driven
/// by the live microphone RMS level. At `audioLevel == 0` the bars
/// settle to a minimum visible height rather than collapsing flat —
/// a capturing-but-silent pill that reads as completely flat is
/// indistinguishable from an idle one, which defeats the point of the
/// distinct state.
///
/// ## Amplitude curve
///
/// Same `sqrt` perceptual curve used by `SineWaveView` so
/// conversational RMS (0.05–0.15) drives visible modulation on a
/// 24pt canvas instead of sub-pixel changes.
///
/// ## Deterministic per-bar phase
///
/// Each bar is offset by a stable phase derived from its index so
/// neighbouring bars animate out of sync — the equaliser looks alive
/// even on steady tone. Phase advances with wall-clock time from the
/// `TimelineView` driver; no stored `@State` timestamp needed.
///
/// ## Why not reuse WaveformView
///
/// `WaveformView` renders a centre-biased silhouette with a base
/// minimum height and a sine silhouette; the spec for hold-to-record
/// is a simpler "7 audio-level-driven bars" that should read as a
/// distinct visual, not a variant of the committed-recording bars.
/// Keeping them separate avoids cross-coupling their tuning.
@MainActor
public struct EqualizerBarsView: View {
    public let audioLevel: Double
    public let tint: Color
    public let barCount: Int

    public init(
        audioLevel: Double,
        tint: Color,
        barCount: Int = 7
    ) {
        self.audioLevel = audioLevel
        self.tint = tint
        self.barCount = barCount
    }

    public var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                let barWidth = max(2, (proxy.size.width - CGFloat(barCount - 1) * Geometry.gap) / CGFloat(barCount))

                HStack(spacing: Geometry.gap) {
                    ForEach(0..<barCount, id: \.self) { index in
                        let h = Geometry.barHeight(
                            barIndex: index,
                            totalBars: barCount,
                            level: audioLevel,
                            phase: t,
                            availableHeight: proxy.size.height
                        )
                        RoundedRectangle(cornerRadius: barWidth / 2, style: .continuous)
                            .fill(tint)
                            .frame(width: barWidth, height: h)
                    }
                }
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
            }
        }
    }

    /// Pure functions driving the bar geometry. Extracted so tests can
    /// pin the clamping + minimum-height + monotonicity contract
    /// without needing a live SwiftUI render.
    public enum Geometry {
        /// Inter-bar gap in points. Tuned so a 120pt wide row shows
        /// balanced bars + gaps at 7-bar count.
        public static let gap: CGFloat = 3.0

        /// Fraction of the canvas height used at `audioLevel = 1.0`.
        public static let maxHeightFactor: CGFloat = 1.0

        /// Minimum bar height as a fraction of the canvas — the
        /// capturing-but-silent baseline so the equaliser never
        /// collapses flat.
        public static let minHeightFactor: CGFloat = 0.18

        public static func clampedLevel(_ raw: Double) -> Double {
            min(1.0, max(0.0, raw))
        }

        public static func barHeight(
            barIndex: Int,
            totalBars: Int,
            level: Double,
            phase: Double,
            availableHeight: CGFloat
        ) -> CGFloat {
            guard totalBars > 0, availableHeight > 0 else { return 0 }
            let clamped = clampedLevel(level)
            let curved = clamped.squareRoot()

            // Per-bar phase offset so neighbours don't animate in lockstep.
            let indexPhase = Double(barIndex) * 0.9
            // ~2 Hz shimmer — slower than a sine wave so bars read as
            // discrete hops rather than a travelling wave.
            let shimmer = 0.5 + 0.5 * sin(phase * 2.0 + indexPhase)

            // Blend: when level is low, bars mostly idle at min; when
            // loud, bars reach near-max. Shimmer adds a small jitter
            // on top regardless of level so nothing freezes.
            let dynamicSpan = (maxHeightFactor - minHeightFactor)
            let shimmerWeight: CGFloat = 0.25
            let levelWeight: CGFloat = 1.0 - shimmerWeight
            let factor = CGFloat(curved) * levelWeight * dynamicSpan
                + CGFloat(shimmer) * shimmerWeight * dynamicSpan * CGFloat(curved)

            let h = availableHeight * (minHeightFactor + factor)
            return min(availableHeight, max(availableHeight * minHeightFactor, h))
        }
    }
}

#Preview("Equaliser — silent (0.0)") {
    EqualizerBarsView(
        audioLevel: 0.0,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 24)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("Equaliser — speaking (0.4)") {
    EqualizerBarsView(
        audioLevel: 0.4,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 24)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}
