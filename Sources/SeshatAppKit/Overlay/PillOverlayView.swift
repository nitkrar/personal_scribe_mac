import SwiftUI
import SeshatCore

/// Pill overlay — the floating surface that tracks the recording / idle /
/// transcribing / download states.
///
/// ## Visual spec (Phase 2 Sprint 2 Lane B1)
/// * Idle pill (Always On mode) — compact capsule with quill + flat
///   wave + "Idle" label.
///   Ref: `plans/seshat_agent_bundle/03_Surfaces/PillOverlayWindow/command_mode_states.png`
///   PANEL 1 (180×34pt).
/// * Recording pill — quill (listening state) + animated waveform +
///   elapsed placeholder + stop glyph. 180×34pt per
///   `command_mode_states.png` PANEL 1 + `recording_states.png` "Pill
///   only" variant.
///   `PulsingDot × 3` from Sprint 1 has been DELETED (PLAN_PHASES.md line
///   291 + DoD line 356).
/// * Transcribing pill — flat wave + quill with ink drip.
///   Ref: `light_mode_states.png` PANEL 3.
/// * Downloading / Loading — keep the Sprint 1 behaviour but wrap in the
///   theme-palette chrome.
/// * Hidden — render `EmptyView`.
///
/// ## Theme compliance
/// All colours resolve from `SeshatTheme.Palette.for(scheme:)` — no raw
/// `Color(hex:)` or `.regularMaterial` material-blur calls. Dark/light
/// parity is automatic via `@Environment(\.colorScheme)`.
@MainActor
public struct PillOverlayView: View {
    @ObservedObject private var model: PillOverlayViewModel

    @Environment(\.colorScheme) private var colorScheme

    /// The 180×34 pill size from `command_mode_states.png` PANEL 1.
    private static let pillWidth: CGFloat = 180
    private static let pillHeight: CGFloat = 34

    /// A wider layout for download / loading messages that don't fit the
    /// 180-wide recording pill.
    private static let wideWidth: CGFloat = 240

    public init(model: PillOverlayViewModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        ZStack {
            switch model.visibility {
            case .hidden:
                EmptyView()
            case .idle:
                idlePill
                    .transition(pillTransition)
            case .downloading(let fraction):
                downloadingPill(fraction: fraction)
                    .transition(pillTransition)
            case .loading:
                loadingPill
                    .transition(pillTransition)
            case .recording:
                recordingPill
                    .transition(pillTransition)
            case .transcribing:
                transcribingPill
                    .transition(pillTransition)
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.82), value: model.visibility)
    }

    // MARK: - Idle

    /// Compact capsule — quill (idle state) + flat wave (handled
    /// internally by `SeshatLogoView.idle`) + "Idle" label.
    /// Per BACKLOG P1 #4 / UX audit BUG-10 — NOT a bare dot.
    private var idlePill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: SeshatTheme.Spacing.iconPadding) {
            SeshatLogoView(size: 20, state: .idle)
                .frame(width: 20, height: 20)

            Text("Idle")
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.secondaryText)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .frame(
            width: Self.pillWidth,
            height: Self.pillHeight,
            alignment: .leading
        )
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("Seshat idle — double-tap option to record")
    }

    // MARK: - Recording

    /// 180×34 recording pill. Horizontal layout:
    /// quill (listening) | waveform | stop glyph.
    /// Elapsed-timer wiring is tracked for Lane B1 follow-up; Phase 2
    /// ships the chrome + waveform composition.
    private var recordingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 6) {
            SeshatLogoView(size: 18, state: .listening)
                .frame(width: 18, height: 18)

            WaveformView(
                audioLevel: $model.audioLevel,
                isActive: .constant(model.isAudioActive),
                decayMode: .animated
            )
            .frame(height: 20)

            Image(systemName: "stop.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.statusRecording)
                .frame(width: 16, height: 16)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .frame(width: Self.pillWidth, height: Self.pillHeight)
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("Seshat recording — tap to stop")
    }

    // MARK: - Transcribing

    /// Flat waveform + quill with ink drip + "Transcribing…" label.
    /// Ref `light_mode_states.png` PANEL 3 + `logo_animation_states.png`
    /// "Transcribing" tile.
    private var transcribingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: SeshatTheme.Spacing.iconPadding) {
            SeshatLogoView(size: 20, state: .transcribing)
                .frame(width: 20, height: 20)

            Text("Transcribing…")
                .font(SeshatTheme.Typography.caption.font.weight(.medium))
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .frame(width: Self.pillWidth, height: Self.pillHeight, alignment: .leading)
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("Seshat transcribing")
    }

    // MARK: - Downloading

    private func downloadingPill(fraction: Double) -> some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let percent = Int((fraction * 100).rounded())

        return HStack(spacing: SeshatTheme.Spacing.iconPadding) {
            SeshatLogoView(size: 18, state: .idle)
                .frame(width: 18, height: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading model… \(percent)%")
                    .font(SeshatTheme.Typography.caption.font.weight(.medium))
                    .foregroundStyle(palette.primaryText)

                ProgressView(value: max(0, min(fraction, 1)))
                    .progressViewStyle(.linear)
                    .tint(palette.brandChampagne)
            }
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .padding(.vertical, 4)
        .frame(width: Self.wideWidth)
        .modifier(PillChrome(palette: palette))
    }

    // MARK: - Loading

    private var loadingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: SeshatTheme.Spacing.iconPadding) {
            SeshatLogoView(size: 18, state: .idle)
                .frame(width: 18, height: 18)

            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.small)
                .tint(palette.brandChampagne)

            Text("Warming up model…")
                .font(SeshatTheme.Typography.caption.font.weight(.medium))
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, SeshatTheme.Spacing.rowPadding)
        .frame(width: Self.wideWidth, height: Self.pillHeight + 6)
        .modifier(PillChrome(palette: palette))
    }

    // MARK: - Helpers

    private var pillTransition: AnyTransition {
        .opacity
            .combined(with: .scale(scale: 0.92))
            .combined(with: .offset(y: 8))
    }
}

/// Shared capsule-background view-modifier so every pill variant gets the
/// same chrome without duplicating the stack.
private struct PillChrome: ViewModifier {
    let palette: SeshatTheme.Palette

    func body(content: Content) -> some View {
        content
            .background {
                Capsule()
                    .fill(palette.elevatedSurface)
                    .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
            }
            .overlay {
                Capsule()
                    .strokeBorder(
                        palette.brandChampagne.opacity(0.18),
                        lineWidth: 0.5
                    )
            }
    }
}

#Preview("PillOverlayView — state tour") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        PillOverlayView(model: previewModel(state: .idle, mode: .alwaysOn))
        PillOverlayView(model: previewModel(
            state: .recording,
            mode: .alwaysOn,
            audioLevel: 0.6
        ))
        PillOverlayView(model: previewModel(state: .transcribing, mode: .alwaysOn))
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}

@MainActor
private func previewModel(
    state: SessionState,
    mode: PillVisibilityMode,
    audioLevel: Double = 0
) -> PillOverlayViewModel {
    let m = PillOverlayViewModel(visibilityMode: mode)
    m.apply(sessionState: state, preparationProgress: nil)
    m.audioLevel = audioLevel
    return m
}
