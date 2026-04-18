import SwiftUI
import SeshatCore

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
/// All colours resolve from `SeshatTheme.Palette.for(scheme:)`. Pill
/// background + stop-red are the scheme-invariant pill tokens
/// (`pillBackground`, `pillStopRed`, `pillForegroundText`). No raw
/// `Color(hex:)` or inline RGB values — grepping for those outside
/// `SeshatTheme.swift` must return zero hits.
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

    static let cornerRadius: CGFloat = 14

    public init(model: PillOverlayViewModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Group {
            switch model.visibility {
            case .hidden:
                EmptyView()
            case .idle:
                idlePill
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
            }
        }
        .animation(
            .spring(response: 0.3, dampingFraction: 0.7),
            value: model.visibility
        )
    }

    // MARK: - Idle

    private var idlePill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack {
            Image(systemName: "waveform")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.brandChampagne.opacity(0.7))
        }
        .frame(width: Self.idleSize.width, height: Self.idleSize.height)
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("Seshat idle — double-tap right Option to record")
    }

    // MARK: - Recording

    private var recordingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 12) {
            // Cancel (passive — tap-to-dismiss affordance carries via the
            // panel's onTap + cancel handling in future wiring).
            Image(systemName: "xmark")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(palette.brandChampagne.opacity(0.7))

            // Animated waveform
            SineWaveView(
                isAnimating: true,
                tint: palette.brandChampagne
            )
            .frame(width: 120, height: 28)

            // Stop button (visual only; the outer panel onTap triggers
            // SessionCoordinator.toggle()).
            Circle()
                .fill(palette.pillStopRed)
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
        .accessibilityLabel("Seshat recording — tap to stop")
    }

    // MARK: - Transcribing

    private var transcribingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(palette.brandChampagne)

            Text("Transcribing…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.pillForegroundText)
        }
        .frame(width: Self.transcribingSize.width, height: Self.transcribingSize.height)
        .modifier(PillChrome(palette: palette))
        .accessibilityElement()
        .accessibilityLabel("Seshat transcribing")
    }

    // MARK: - Done

    private var donePill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return Image(systemName: "checkmark")
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(palette.brandChampagne)
            .frame(width: Self.doneSize.width, height: Self.doneSize.height)
            .modifier(PillChrome(palette: palette))
            .accessibilityElement()
            .accessibilityLabel("Transcription copied to clipboard")
    }

    // MARK: - Downloading

    private func downloadingPill(fraction: Double) -> some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let percent = Int((fraction * 100).rounded())

        return HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.brandChampagne)

            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading model \(percent)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(palette.pillForegroundText)

                ProgressView(value: max(0, min(fraction, 1)))
                    .progressViewStyle(.linear)
                    .tint(palette.brandChampagne)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, 12)
        .frame(width: Self.downloadingSize.width, height: Self.downloadingSize.height)
        .modifier(PillChrome(palette: palette))
    }

    // MARK: - Loading

    private var loadingPill: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        return HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
                .tint(palette.brandChampagne)

            Text("Warming up…")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(palette.pillForegroundText)
        }
        .frame(width: Self.loadingSize.width, height: Self.loadingSize.height)
        .modifier(PillChrome(palette: palette))
    }
}

/// Shared rounded-rectangle chrome for every pill variant. Dark navy
/// fill, soft shadow, no border — per Claude's minimalist spec.
///
/// ## Fuzzy-edge fix (2026-04-18)
/// The system `NSPanel.hasShadow = true` drew a fringe outside the
/// rounded corners. Fix: NSPanel shadow disabled at the panel layer;
/// the chrome here applies a hard `.clipShape` BEFORE `.shadow(...)`
/// so the shadow is composited on a clean pixel boundary.
private struct PillChrome: ViewModifier {
    let palette: SeshatTheme.Palette

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(
                    cornerRadius: PillOverlayView.cornerRadius,
                    style: .continuous
                )
                .fill(palette.pillBackground.opacity(0.94))
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

#Preview("PillOverlayView — state tour") {
    VStack(spacing: 16) {
        PillOverlayView(model: previewModel(visibility: .idle))
        PillOverlayView(model: previewModel(visibility: .recording))
        PillOverlayView(model: previewModel(visibility: .transcribing))
        PillOverlayView(model: previewModel(visibility: .done))
        PillOverlayView(model: previewModel(visibility: .loading))
        PillOverlayView(model: previewModel(visibility: .downloading(fractionCompleted: 0.42)))
    }
    .padding(24)
    .background(Color(.windowBackgroundColor))
    .preferredColorScheme(.dark)
}

@MainActor
private func previewModel(visibility: PillOverlayViewModel.Visibility) -> PillOverlayViewModel {
    let m = PillOverlayViewModel(visibilityMode: .alwaysOn)
    // Drive the internal state machine via apply(); the stub SessionState
    // isn't public on PreviewModel, so reuse alwaysOn + matching session.
    switch visibility {
    case .hidden:
        m.setVisibilityMode(.hidden)
    case .idle:
        m.apply(sessionState: .idle, preparationProgress: nil)
    case .recording:
        m.apply(sessionState: .recording, preparationProgress: nil)
    case .transcribing:
        m.apply(sessionState: .transcribing, preparationProgress: nil)
    case .done:
        // Simulate a transcribing → idle transition to enter .done.
        m.apply(sessionState: .transcribing, preparationProgress: nil)
        m.apply(sessionState: .idle, preparationProgress: nil)
    case .downloading(let fraction):
        m.apply(sessionState: .idle, preparationProgress: ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: fraction,
            receivedBytes: Int64(fraction * 100),
            expectedBytes: 100
        ))
    case .loading:
        m.apply(sessionState: .idle, preparationProgress: ModelDownloadProgress(
            phase: .loading,
            fractionCompleted: 1.0,
            receivedBytes: 100,
            expectedBytes: 100
        ))
    }
    return m
}
