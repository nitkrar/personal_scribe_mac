import SwiftUI

/// The Seshat quill — the single source of truth for the brand mark.
///
/// Animation states come from
/// `plans/seshat_agent_bundle/01_Foundations/assets/logo_animation_states.png`:
/// * **idle** — quill + a slow flat-ish wave.
/// * **listening** — quill + fast animated waveform through the quill.
/// * **transcribing** — flat wave + ink drip from the nib.
/// * **error** — quill alone (no wave), used to indicate permission / mic
///   error states.
///
/// **Do NOT instantiate this view inside the menu bar `NSStatusItem`.** The
/// status item uses a static `NSImage` template exported from the quill
/// mark (see `Assets.xcassets/StatusBarIcon.imageset/`). This rule is
/// locked in by `03_Surfaces/MenuBarMenu/IMPORTANT.md` and the Phase 2
/// plan line 344.
public struct SeshatLogoView: View {
    // MARK: - Animation state

    /// Visual states the logo can be in. Strings are stable identifiers
    /// safe to persist or log.
    public enum AnimationState: String, CaseIterable, Sendable, Equatable {
        case idle
        case listening
        case transcribing
        case error
    }

    // MARK: - Geometry helpers

    /// Pure helpers used by the view and the tests. Keeping them on a
    /// separate nested type makes the TDD surface observable without
    /// needing to render the view.
    ///
    /// Instances of `Geometry` hold the resolved `strokeWidth` for a
    /// given logo `size`; static methods answer state-driven questions
    /// ("does this state show a waveform?") without an instance.
    public struct Geometry: Sendable, Equatable {
        public let size: CGFloat
        public let strokeWidth: CGFloat

        public init(size: CGFloat) {
            self.size = size
            self.strokeWidth = Geometry.strokeWidth(for: size)
        }

        /// Stroke width scales linearly with the logo size; 24pt → 1.5,
        /// 96pt → 6.0. Clamped to a minimum of 1 so the mark never
        /// disappears at small sizes.
        public static func strokeWidth(for size: CGFloat) -> CGFloat {
            max(1.0, size / 16.0)
        }

        public static func showsWaveform(for state: AnimationState) -> Bool {
            switch state {
            case .idle, .listening, .transcribing: return true
            case .error: return false
            }
        }

        public static func showsInkDrip(for state: AnimationState) -> Bool {
            state == .transcribing
        }

        /// Animation speed in cycles-per-second. 0 = no animation.
        public static func animationSpeed(for state: AnimationState) -> Double {
            switch state {
            case .idle: return 0.4          // slow, breathing
            case .listening: return 1.6     // lively
            case .transcribing: return 0.0  // flat wave
            case .error: return 0.0
            }
        }
    }

    // MARK: - Stored state

    public let size: CGFloat
    public let state: AnimationState
    public let explicitTint: Color?

    @Environment(\.colorScheme) private var colorScheme

    public init(
        size: CGFloat,
        state: AnimationState = .idle,
        tint: Color? = nil
    ) {
        self.size = size
        self.state = state
        self.explicitTint = tint
    }

    // MARK: - Body

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let tint = explicitTint ?? palette.brandChampagne
        let stroke = Geometry.strokeWidth(for: size)
        let speed = Geometry.animationSpeed(for: state)
        let showsWave = Geometry.showsWaveform(for: state)
        let showsDrip = Geometry.showsInkDrip(for: state)

        ZStack {
            // Waveform through / beside the quill.
            //
            // Only enable `TimelineView(.animation)` when the state actually
            // animates. For transcribing / error we render a static flat
            // wave (or none) without a ticking timeline.
            if showsWave {
                if speed > 0 {
                    TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                        let phase = context.date.timeIntervalSinceReferenceDate * speed
                        LogoWaveShape(
                            phase: phase,
                            amplitudeFactor: waveAmplitudeFactor(for: state)
                        )
                        .stroke(tint, style: StrokeStyle(
                            lineWidth: stroke,
                            lineCap: .round
                        ))
                    }
                } else {
                    LogoWaveShape(
                        phase: 0,
                        amplitudeFactor: waveAmplitudeFactor(for: state)
                    )
                    .stroke(tint, style: StrokeStyle(
                        lineWidth: stroke,
                        lineCap: .round
                    ))
                }
            }

            // Static quill shape
            QuillShape()
                .stroke(tint, style: StrokeStyle(
                    lineWidth: stroke,
                    lineCap: .round,
                    lineJoin: .round
                ))

            // Ink drip in transcribing state
            if showsDrip {
                InkDripShape()
                    .fill(tint)
            }
        }
        .frame(width: size, height: size)
        .animation(.easeInOut(duration: 0.25), value: state)
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel(for: state))
    }

    private func waveAmplitudeFactor(for state: AnimationState) -> Double {
        switch state {
        case .idle: return 0.08
        case .listening: return 0.18
        case .transcribing: return 0.0
        case .error: return 0.0
        }
    }

    private func accessibilityLabel(for state: AnimationState) -> String {
        switch state {
        case .idle: return "Seshat quill, idle"
        case .listening: return "Seshat quill, listening"
        case .transcribing: return "Seshat quill, transcribing"
        case .error: return "Seshat quill, error"
        }
    }
}

// MARK: - Shape geometry

/// Stylised diagonal quill path approximating the reference asset. Drawn in
/// a unit square; callers stroke with the tint colour.
struct QuillShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height

        // Nib at lower-left
        let nib = CGPoint(x: w * 0.28, y: h * 0.82)
        // Base of feather (above nib)
        let shaftBase = CGPoint(x: w * 0.38, y: h * 0.70)
        // Tip of feather (upper-right)
        let tip = CGPoint(x: w * 0.78, y: h * 0.18)

        // Central shaft
        p.move(to: nib)
        p.addLine(to: CGPoint(x: w * 0.32, y: h * 0.76))
        p.addQuadCurve(
            to: tip,
            control: CGPoint(x: w * 0.40, y: h * 0.30)
        )

        // Outer feather edge (leading edge)
        p.move(to: shaftBase)
        p.addQuadCurve(
            to: tip,
            control: CGPoint(x: w * 0.78, y: h * 0.62)
        )

        // Inner feather edge (trailing edge)
        p.move(to: shaftBase)
        p.addQuadCurve(
            to: tip,
            control: CGPoint(x: w * 0.30, y: h * 0.35)
        )

        // A few barbs (feather hairs) perpendicular to the shaft
        let barbCount = 5
        for i in 1...barbCount {
            let t = CGFloat(i) / CGFloat(barbCount + 1)
            let shaft = CGPoint(
                x: shaftBase.x + (tip.x - shaftBase.x) * t,
                y: shaftBase.y + (tip.y - shaftBase.y) * t
            )
            let perp = CGVector(dx: -(tip.y - shaftBase.y), dy: (tip.x - shaftBase.x))
            let len = sqrt(perp.dx * perp.dx + perp.dy * perp.dy)
            guard len > 0 else { continue }
            let scale = min(w, h) * 0.10
            let off = CGVector(dx: perp.dx / len * scale, dy: perp.dy / len * scale)
            p.move(to: shaft)
            p.addLine(to: CGPoint(x: shaft.x + off.dx, y: shaft.y + off.dy))
        }

        return p
    }
}

/// Horizontal sinusoidal wave that passes through the mid-height of the
/// quill. `phase` advances over time; `amplitudeFactor` is a fraction of
/// the height.
struct LogoWaveShape: Shape {
    var phase: Double
    var amplitudeFactor: Double

    var animatableData: Double {
        get { phase }
        set { phase = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let midY = rect.midY + rect.height * 0.05
        let amp = rect.height * CGFloat(amplitudeFactor)
        let w = rect.width

        p.move(to: CGPoint(x: 0, y: midY))
        let step: CGFloat = 2
        var x: CGFloat = 0
        while x <= w {
            let t = Double(x / w) * .pi * 4 + phase * .pi * 2
            let y = midY + amp * CGFloat(sin(t))
            p.addLine(to: CGPoint(x: x, y: y))
            x += step
        }
        return p
    }
}

/// Small ink-drop beneath the nib — used only in the `.transcribing` state.
struct InkDripShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        let center = CGPoint(x: w * 0.28, y: h * 0.92)
        let r = min(w, h) * 0.035
        p.addEllipse(in: CGRect(
            x: center.x - r,
            y: center.y - r,
            width: r * 2,
            height: r * 2
        ))
        return p
    }
}

#Preview("Seshat Logo — all states") {
    HStack(spacing: 24) {
        VStack {
            SeshatLogoView(size: 96, state: .idle)
            Text("idle").font(SeshatTheme.Typography.caption.font)
        }
        VStack {
            SeshatLogoView(size: 96, state: .listening)
            Text("listening").font(SeshatTheme.Typography.caption.font)
        }
        VStack {
            SeshatLogoView(size: 96, state: .transcribing)
            Text("transcribing").font(SeshatTheme.Typography.caption.font)
        }
        VStack {
            SeshatLogoView(size: 96, state: .error)
            Text("error").font(SeshatTheme.Typography.caption.font)
        }
    }
    .padding(24)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
