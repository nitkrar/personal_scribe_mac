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
/// * `isAnimating` — when `true`, the wave's phase animates across
///   a 1.2-second loop. When `false`, the phase eases back to zero
///   over 300ms (used when transitioning out of the recording state).
@MainActor
public struct SineWaveView: View {
    public let isAnimating: Bool
    public let tint: Color

    @State private var phase: Double = 0

    public init(isAnimating: Bool, tint: Color) {
        self.isAnimating = isAnimating
        self.tint = tint
    }

    public var body: some View {
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
        .onAppear {
            startAnimationIfNeeded()
        }
        .onChange(of: isAnimating) { _, newValue in
            if newValue {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 2 * .pi
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    phase = 0
                }
            }
        }
    }

    private func startAnimationIfNeeded() {
        guard isAnimating else { return }
        withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
            phase = 2 * .pi
        }
    }
}

#Preview("SineWaveView — animating") {
    SineWaveView(
        isAnimating: true,
        tint: SeshatTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(SeshatTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}

#Preview("SineWaveView — static") {
    SineWaveView(
        isAnimating: false,
        tint: SeshatTheme.Palette.dark.brandChampagne
    )
    .frame(width: 120, height: 28)
    .padding()
    .background(SeshatTheme.Palette.dark.pillBackground)
    .preferredColorScheme(.dark)
}
