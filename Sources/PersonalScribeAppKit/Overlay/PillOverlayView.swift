import SwiftUI
import PersonalScribeCore

/// Pill overlay — the floating surface that tracks the recording /
/// transcribing / done / download visual states.
///
/// ## Visual spec (Sprint 2 dogfood redesign, 2026-04-18)
/// Claude's WisprFlow-inspired compact pill, four main states:
///
/// | State         | Size    | Content                                              |
/// |---------------|---------|------------------------------------------------------|
/// | `.idle`       | 80×28pt | champagne quill mark centered; no text               |
/// | `.recording`  | 200×36  | × cancel | animated sine wave | red stop button      |
/// | `.transcribing` | 140×36 | small spinner + "Transcribing…" caption             |
/// | `.done`       | 80×28   | champagne checkmark; auto-returns to idle after ~1s |
///
/// ## Non-main-flow states
/// * `.downloading(fraction)` — 240×36 with progress bar (model download).
/// * `.loading` — 140×36 with spinner (model warm-up).
/// * `.hidden` — `EmptyView()` (pill not rendered).
///
/// ## Theme compliance
/// The pill background is scheme-invariant (always dark navy `#1A1B2E`).
/// All pill FOREGROUND colours therefore also use the scheme-invariant
/// `PersonalScribeTheme.Pill.Dark.*` constants — NOT the window-palette
/// `brandChampagne` token, which resolves to a low-contrast grey-brown
/// in light mode. This ensures the spinner, waveform, icons, and text
/// remain legible regardless of the user's WindowTint preference.
@MainActor
public struct PillOverlayView: View {
    @ObservedObject private var model: PillOverlayViewModel

    @Environment(\.colorScheme) private var colorScheme

    // Pill dimension constants — authoritative sizes per Claude's Pill UX
    // Prompt (spec §2). Kept as static lets so presenter / tests can
    // reference them. `idleSize` retains the original 80×28 from the
    // pre-spec pill; new / updated sizes follow the spec tables.
    static let idleSize = CGSize(width: 80, height: 28)
    /// 160×36 — Hold-to-Record (spec §2b). 7-bar equaliser + clay border.
    static let holdToRecordSize = CGSize(width: 160, height: 36)
    /// 220×36 — committed Recording (spec §2c). Was 200×36 pre-spec.
    static let recordingSize = CGSize(width: 220, height: 36)
    /// 160×36 — Transcribing (spec §2d). Was 140×36 pre-spec.
    static let transcribingSize = CGSize(width: 160, height: 36)
    /// 100×32 — Done (spec §2e). Was 80×28 pre-spec.
    static let doneSize = CGSize(width: 100, height: 32)
    static let downloadingSize = CGSize(width: 240, height: 36)
    static let loadingSize = CGSize(width: 140, height: 36)
    static let errorSize = CGSize(width: 220, height: 36)

    /// Corner radius for idle (spec §2a — 14pt) and a few non-spec
    /// states. `PillChrome(state:)` picks this per state; the
    /// hold-to-record / recording / transcribing variants use 18pt per
    /// spec §2b-d.
    static let cornerRadius: CGFloat = 14
    /// 18pt corner radius for the active-recording family of pills
    /// (hold-to-record, recording, transcribing). Spec §2b, §2c, §2d.
    static let activeCornerRadius: CGFloat = 18
    /// 16pt corner radius for the done confirmation. Spec §2e.
    static let doneCornerRadius: CGFloat = 16

    // Pill foreground tokens — selected based on the resolved panel
    // appearance (which follows the user's Dark / Light / System
    // preference in Settings). colorScheme reflects the NSPanel
    // appearance set by PillOverlayPresenter.applyResolvedAppearance().
    //
    // Dark panel  → Pill.Dark.*  (champagne on navy)
    // Light panel → Pill.Light.* (dark ink on pale cream)
    private var fg: Color {
        colorScheme == .dark
            ? PersonalScribeTheme.Pill.Dark.waveform
            : PersonalScribeTheme.Pill.Light.waveform
    }
    private var fgDim: Color {
        colorScheme == .dark
            ? PersonalScribeTheme.Pill.Dark.cancel
            : PersonalScribeTheme.Pill.Light.cancel
    }
    private var fgStop: Color {
        colorScheme == .dark
            ? PersonalScribeTheme.Pill.Dark.stop
            : PersonalScribeTheme.Pill.Light.stop
    }

    public init(model: PillOverlayViewModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Group {
            switch model.visibility {
            case .hidden, .cancelled:
                // Phase 1 placeholder for `.cancelled`: just hide the
                // pill. Phase 3 replaces this with the Cancel Card at
                // the same screen anchor.
                EmptyView()
            case .idle:
                idlePill
            case .holdToRecord:
                holdToRecordPill
            case .recording:
                recordingPill
            case .transcribing:
                transcribingPill
            case .done:
                donePill
            case .downloading(let fraction):
                downloadingPill(fraction: fraction)
            case .loading:
                loadingPill
            case .error(let message):
                errorPill(message: message)
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.7),
            value: model.visibility
        )
    }

    // MARK: - Idle

    private var idlePill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return HStack {
            // Logo uses the scheme-invariant champagne fg token.
            PersonalScribeLogoView(color: fg.opacity(0.9))
                .frame(width: 14, height: 14)
        }
        .frame(width: Self.idleSize.width, height: Self.idleSize.height)
        .modifier(PillChrome(palette: palette, borderStyle: .idle))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) idle — double-tap right Option to record")
    }

    // MARK: - Hold-to-Record (spec §2b)

    /// 7-bar vertical equaliser shown while the user is holding the
    /// record modifier. Clay border identifies the active / capturing
    /// state; bar heights are audio-level-driven (Phase 2 note: if the
    /// incoming audio level is zero the bars idle at the minimum
    /// height rather than falling to zero — keeps the visual alive).
    private var holdToRecordPill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return EqualizerBarsView(
            audioLevel: model.audioLevel,
            tint: fg,
            barCount: 7
        )
        .frame(width: 120, height: 24)
        .frame(width: Self.holdToRecordSize.width, height: Self.holdToRecordSize.height)
        .modifier(PillChrome(palette: palette, borderStyle: .active))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) hold-to-record — release to transcribe")
    }

    // MARK: - Recording (spec §2c)

    private var recordingPill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 12) {
            // Cancel glyph — dimmed secondary fg.
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(fgDim)

            // Voice-modulated waveform.
            SineWaveView(
                audioLevel: model.audioLevel,
                decayMode: .animated,
                tint: fg
            )
            .frame(width: 140, height: 28)

            // Stop button.
            Circle()
                .fill(fgStop)
                .frame(width: 18, height: 18)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white)
                        .frame(width: 7, height: 7)
                )
        }
        .frame(width: Self.recordingSize.width, height: Self.recordingSize.height)
        .modifier(PillChrome(palette: palette, borderStyle: .active))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) recording — tap to stop")
    }

    // MARK: - Transcribing (spec §2d)

    private var transcribingPill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(fg)

            Text("Transcribing…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)
        }
        .frame(width: Self.transcribingSize.width, height: Self.transcribingSize.height)
        .modifier(PillChrome(palette: palette, borderStyle: .transcribing))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) transcribing")
    }

    // MARK: - Done (spec §2e)

    private var donePill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let green = PersonalScribeTheme.Pill.Border.doneColor

        return Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(green)
            .frame(width: Self.doneSize.width, height: Self.doneSize.height)
            .modifier(PillChrome(palette: palette, borderStyle: .done))
            .accessibilityElement()
            .accessibilityLabel("Transcription copied to clipboard")
    }

    // MARK: - Downloading

    private func downloadingPill(fraction: Double) -> some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let percent = Int((fraction * 100).rounded())

        return HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)

            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading model \(percent)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(fg)

                ProgressView(value: max(0, min(fraction, 1)))
                    .progressViewStyle(.linear)
                    .tint(fg)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.downloadingSize.width, height: Self.downloadingSize.height)
        .modifier(PillChrome(palette: palette))
    }

    // MARK: - Loading

    private var loadingPill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(fg)

            Text("Loading model…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)
        }
        .frame(width: Self.loadingSize.width, height: Self.loadingSize.height)
        .modifier(PillChrome(palette: palette))
    }

    // MARK: - Error

    private func errorPill(message: String) -> some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(fgStop)   // red — same stop/error red

            Text(message)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(width: Self.errorSize.width, height: Self.errorSize.height)
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) error: \(message)")
    }
}

/// Per-state border styling (pill UX spec §2 + §4). Drives the
/// rounded-rect stroke `PillChrome` paints on top of the gradient /
/// specular layers. Corner radius travels alongside because the idle
/// state uses 14pt while the active family uses 18pt per spec.
struct PillBorderStyle: Equatable {
    let strokeColor: Color
    let lineWidth: CGFloat
    let cornerRadius: CGFloat

    // Corner radii are inlined here rather than referenced from
    // `PillOverlayView.cornerRadius` etc. — `PillOverlayView` is
    // MainActor-isolated so its static members can't be used in a
    // non-isolated static initializer. Values stay in sync with the
    // `PillOverlayView.*CornerRadius` constants; the spec table is
    // the authoritative source (§2).
    /// 14pt, 1px white 8% — idle / neutral states.
    static let idle = PillBorderStyle(
        strokeColor: PersonalScribeTheme.Pill.Border.idleColor,
        lineWidth: PersonalScribeTheme.Pill.Border.idleWidth,
        cornerRadius: 14
    )

    /// 18pt, 1.5px Clay #C9A96E — hold-to-record + committed recording.
    static let active = PillBorderStyle(
        strokeColor: PersonalScribeTheme.Pill.Border.clayColor,
        lineWidth: PersonalScribeTheme.Pill.Border.activeWidth,
        cornerRadius: 18
    )

    /// 18pt, 1px Champagne 40% — transcribing.
    static let transcribing = PillBorderStyle(
        strokeColor: PersonalScribeTheme.Pill.Border.transcribingColor,
        lineWidth: PersonalScribeTheme.Pill.Border.transcribingWidth,
        cornerRadius: 18
    )

    /// 16pt, 1px Green #50C878 — done confirmation.
    static let done = PillBorderStyle(
        strokeColor: PersonalScribeTheme.Pill.Border.doneColor,
        lineWidth: PersonalScribeTheme.Pill.Border.doneWidth,
        cornerRadius: 16
    )
}

/// Shared rounded-rectangle chrome for every pill variant.
///
/// ## 3D depth treatment (2026-04-20)
/// A vertical gradient fill (top face slightly lighter than the base
/// colour) combined with a hairline specular rim and a single clean
/// shadow gives the pill a floating quality on dark desktops without
/// any blur or NSVisualEffectView overhead.
///
/// ## State-aware border (pill UX spec §4, 2026-04-21)
/// The `borderStyle` parameter selects stroke colour + width + corner
/// radius per state. Idle / downloading / loading / error reuse the
/// `PillBorderStyle.idle` neutral rim; hold-to-record and committed
/// recording use `.active` (clay 1.5px); transcribing uses
/// `.transcribing` (champagne 40%); done uses `.done` (green 1px).
///
/// ## Fuzzy-edge fix (2026-04-18)
/// NSPanel shadow disabled at the panel layer; `.clipShape` applied
/// BEFORE `.shadow` so the shadow composites on a clean pixel boundary.
private struct PillChrome: ViewModifier {
    let palette: PersonalScribeTheme.Palette
    let borderStyle: PillBorderStyle

    init(palette: PersonalScribeTheme.Palette, borderStyle: PillBorderStyle = .idle) {
        self.palette = palette
        self.borderStyle = borderStyle
    }

    func body(content: Content) -> some View {
        let base = palette.pillBackground
        let radius = borderStyle.cornerRadius
        content
            .background {
                RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
                // Vertical gradient: top face ~7% brighter than base.
                .fill(base.opacity(0.94))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: radius,
                        style: .continuous
                    )
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.07), Color.clear],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                // State-aware border stroke — see `PillBorderStyle`.
                .overlay {
                    RoundedRectangle(
                        cornerRadius: radius,
                        style: .continuous
                    )
                    .stroke(borderStyle.strokeColor, lineWidth: borderStyle.lineWidth)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: borderStyle.cornerRadius,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
