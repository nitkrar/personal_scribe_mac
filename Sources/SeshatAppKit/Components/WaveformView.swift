import SwiftUI

/// Horizontal audio-level waveform — a row of small vertical bars whose
/// heights animate with the live microphone level.
///
/// ## Draw frequency
///
/// Plan-level decision (PLAN_PHASES.md line 351, confirmed in Sprint 1
/// context): `TimelineView(.animation)` is enabled **only while the
/// `isActive` binding is true**. When `isActive` is `false` (e.g. the
/// idle pill is showing), the view redraws purely in response to
/// `audioLevel` changes via SwiftUI's normal binding-driven invalidation
/// path. This prevents a 60Hz redraw from running on the always-on idle
/// pill.
///
/// ## Inputs
///
/// * `audioLevel` — normalized 0…1 RMS level. Clamped defensively
///   inside the view; values outside range do not crash.
/// * `isActive` — whether we're currently recording / receiving a live
///   stream. Drives the animation mode.
///
/// ## Usage
///
/// ```swift
/// WaveformView(
///     audioLevel: $viewModel.level,
///     isActive: $viewModel.isRecording
/// )
/// .frame(height: 24)
/// ```
public struct WaveformView: View {
    public static let defaultBarCount: Int = 32

    @Binding private var audioLevel: Double
    @Binding private var isActive: Bool

    /// The tint used for bars. When `nil`, resolves from the theme's
    /// `brandChampagne` (idle) or `statusRecording` (active) token.
    private let explicitTint: Color?

    /// How many vertical bars to render.
    private let barCount: Int

    @Environment(\.colorScheme) private var colorScheme

    public init(
        audioLevel: Binding<Double>,
        isActive: Binding<Bool>,
        barCount: Int = WaveformView.defaultBarCount,
        tint: Color? = nil
    ) {
        self._audioLevel = audioLevel
        self._isActive = isActive
        self.barCount = barCount
        self.explicitTint = tint
    }

    // Exposed for tests.
    internal var currentAudioLevel: Double { audioLevel }
    internal var currentIsActive: Bool { isActive }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let tint = explicitTint ?? (isActive
            ? palette.statusRecording
            : palette.brandChampagne)

        GeometryReader { proxy in
            ZStack {
                if isActive {
                    // Live: animate via TimelineView so bars shimmer even if
                    // audioLevel momentarily plateaus.
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        bars(
                            in: proxy.size,
                            tint: tint,
                            phase: context.date.timeIntervalSinceReferenceDate * 2.0
                        )
                    }
                } else {
                    // Idle: render once per audioLevel change. NO TimelineView.
                    bars(
                        in: proxy.size,
                        tint: tint,
                        phase: 0.0
                    )
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel(isActive
            ? "Audio level waveform, recording"
            : "Audio level waveform, idle")
    }

    private func bars(
        in size: CGSize,
        tint: Color,
        phase: Double
    ) -> some View {
        let level = Geometry.clampedLevel(audioLevel)
        let gap: CGFloat = max(1, size.width / CGFloat(barCount * 4))
        let barWidth = max(1, (size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))

        return HStack(spacing: gap) {
            ForEach(0..<barCount, id: \.self) { index in
                let h = Geometry.barHeight(
                    barIndex: index,
                    totalBars: barCount,
                    level: level,
                    phase: phase,
                    availableHeight: size.height
                )
                Capsule()
                    .fill(tint)
                    .frame(width: barWidth, height: h)
            }
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Geometry helpers

    /// Pure functions that drive bar sizing. Moved to a nested `enum` so
    /// tests can verify behaviour without rendering SwiftUI.
    public enum Geometry {
        public static func clampedLevel(_ raw: Double) -> Double {
            min(1.0, max(0.0, raw))
        }

        /// Compute the height of a single bar. The profile blends three
        /// ingredients:
        ///
        /// 1. A **base minimum** so idle bars don't disappear.
        /// 2. A **sinusoidal silhouette** across the bar index — this is
        ///    what makes the waveform look wave-shaped.
        /// 3. The **audio level**, which scales the silhouette up towards
        ///    `availableHeight`.
        public static func barHeight(
            barIndex: Int,
            totalBars: Int,
            level: Double,
            phase: Double,
            availableHeight: CGFloat
        ) -> CGFloat {
            guard totalBars > 0, availableHeight > 0 else { return 0 }
            let clamped = clampedLevel(level)
            let base: CGFloat = availableHeight * 0.12 // minimum visible height
            let t = Double(barIndex) / Double(max(totalBars - 1, 1))
            // Silhouette: 0.5 + 0.5*sin(...) so always 0…1; offset per-bar
            // so bars don't animate in unison.
            let silhouette = 0.5 + 0.5 * sin(phase + t * .pi * 2.0)
            // Emphasise centre bars — a slight gaussian-like bump so the
            // shape reads as a waveform even at zero level.
            let centreBias = 1.0 - abs(t - 0.5) * 1.2
            let centreWeighted = max(0.2, centreBias)
            let scaled = CGFloat(silhouette * clamped + (1.0 - clamped) * 0.1) * centreWeighted
            let dynamic = scaled * (availableHeight - base)
            return min(availableHeight, base + dynamic)
        }
    }
}

#Preview("Waveform — idle vs active") {
    VStack(spacing: 20) {
        WaveformView(
            audioLevel: .constant(0.0),
            isActive: .constant(false)
        )
        .frame(height: 24)

        WaveformView(
            audioLevel: .constant(0.6),
            isActive: .constant(true)
        )
        .frame(height: 24)
    }
    .padding(24)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
