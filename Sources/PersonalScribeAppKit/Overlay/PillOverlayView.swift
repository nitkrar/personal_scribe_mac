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

    // Pill dimension constants — authoritative sizes per Claude's spec.
    // Kept as static lets so presenter / tests can reference them.
    static let idleSize = CGSize(width: 80, height: 28)
    static let recordingSize = CGSize(width: 200, height: 36)
    static let transcribingSize = CGSize(width: 140, height: 36)
    static let doneSize = CGSize(width: 80, height: 28)
    static let downloadingSize = CGSize(width: 240, height: 36)
    static let loadingSize = CGSize(width: 140, height: 36)
    static let errorSize = CGSize(width: 220, height: 36)

    static let cornerRadius: CGFloat = 14

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
                // Phase 1 placeholder: reuse the committed-recording
                // pill visuals while we hold. Phase 2 introduces the
                // 160×36 7-bar equaliser + clay border per the spec.
                recordingPill
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
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) idle — double-tap right Option to record")
    }

    // MARK: - Recording

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
            .frame(width: 120, height: 28)

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
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) recording — tap to stop")
    }

    // MARK: - Transcribing

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
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) transcribing")
    }

    // MARK: - Done

    private var donePill: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)

        return Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(fg)
            .frame(width: Self.doneSize.width, height: Self.doneSize.height)
            .modifier(PillChrome(palette: palette))
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

/// Shared rounded-rectangle chrome for every pill variant.
///
/// ## 3D depth treatment (2026-04-20)
/// A vertical gradient fill (top face slightly lighter than the base
/// colour) combined with a hairline specular rim and a single clean
/// shadow gives the pill a floating quality on dark desktops without
/// any blur or NSVisualEffectView overhead.
///
/// ## Fuzzy-edge fix (2026-04-18)
/// NSPanel shadow disabled at the panel layer; `.clipShape` applied
/// BEFORE `.shadow` so the shadow composites on a clean pixel boundary.
private struct PillChrome: ViewModifier {
    let palette: PersonalScribeTheme.Palette

    func body(content: Content) -> some View {
        let base = palette.pillBackground
        content
            .background {
                RoundedRectangle(
                    cornerRadius: PillOverlayView.cornerRadius,
                    style: .continuous
                )
                // Vertical gradient: top face ~7% brighter than base.
                .fill(base.opacity(0.94))
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PillOverlayView.cornerRadius,
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
                // Specular rim — 1px white stroke at low opacity.
                .overlay {
                    RoundedRectangle(
                        cornerRadius: PillOverlayView.cornerRadius,
                        style: .continuous
                    )
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: PillOverlayView.cornerRadius,
                    style: .continuous
                )
            )
            .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
