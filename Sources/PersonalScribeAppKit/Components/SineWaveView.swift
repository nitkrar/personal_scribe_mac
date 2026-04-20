import SwiftUI

/// Animated sine-wave SwiftUI view for the pill overlay's recording
/// state. Procedural — no audio input required; the wave is a simple
/// phase-animated sinusoid drawn via `Canvas`.
///
/// Reference: WisprFlow-style pill spec (Sprint 2 dogfood rewrite,
/// 2026-04-18). Replaces Sprint 1's audio-level-driven `WaveformView`
/// inside the recording pill — the audio-level approach proved jittery
/// at low signal levels; a procedural wave gives a cleaner "recording"
/// signal.
///
/// ## Parameters
/// * `isAnimating` — when `true`, phase is driven by
///   `TimelineView(.animation)` at ~30 fps, looping over a 1.2-second
///   period. When `false`, the canvas renders once at phase 0.
///
/// `Canvas` does NOT automatically redraw across implicit
/// (`withAnimation`) interpolation of a `@State` it reads. An explicit
/// timeline driver is required to cause per-frame re-execution of the
/// draw closure; `WaveformView` uses the same pattern for its
/// audio-driven render.
@MainActor
public struct SineWaveView: View {
    public let isAnimating: Bool
    public let tint: Color

    private static let loopPeriod: Double = 1.2

    public init(isAnimating: Bool, tint: Color) {
        self.isAnimating = isAnimating
        self.tint = tint
    }

    public var body: some View {
        if isAnimating {
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                waveCanvas(phase: Self.phase(for: context.date))
            }
        } else {
            waveCanvas(phase: 0)
        }
    }

    @ViewBuilder
    private func waveCanvas(phase: Double) -> some View {
        Canvas { context, size in
            var path = Path()
            let amplitude: CGFloat = 4
            let frequency: CGFloat = 2.5
            let w = size.width
            let h = size.height

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
}

#Preview("SineWaveView — animating") {
    SineWaveView(
        isAnimating: true,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("SineWaveView — static") {
    SineWaveView(
        isAnimating: false,
        tint: PersonalScribeTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(PersonalScribeTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}
