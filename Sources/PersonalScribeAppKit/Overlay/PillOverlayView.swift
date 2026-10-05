import SwiftUI
import PersonalScribeCore

/// Pill overlay — the floating surface that tracks the recording /
/// transcribing / download visual states.
///
/// ## Visual spec (Sprint 2 dogfood redesign, 2026-04-18)
/// Shared state layouts rendered at Classic or Mini metrics:
///
/// | State         | Size    | Content                                              |
/// |---------------|---------|------------------------------------------------------|
/// | `.idle`       | 80×28 / 40×16 | champagne quill centered                    |
/// | `.idle` hover | 82×36 / 66×30 | mode (when useful) + record circles         |
/// | `.recording`  | 220×36 / 110×20 | pause + waveform + stop; Mini expands on hover |
/// | `.paused`     | 220×36 / 170×30 | resume + elapsed time + stop               |
/// | `.transcribing` | 220×36 / 110×20 | centered spinner at recording-rest size  |
///
/// ## Non-main-flow states
/// * `.downloading(fraction)` — progress bar for model download.
/// * `.loading` — spinner for model warm-up.
/// * `.hidden` — `EmptyView()` (pill not rendered).
///
/// ## Theme compliance
/// The pill follows the Pill theme setting (Dark / Light / System) via
/// the panel appearance set by `PillOverlayPresenter`: surface from
/// `PersonalScribeTheme.Pill.surface(for:)` (navy / cream) and
/// foreground from `Pill.Dark.*` / `Pill.Light.*` — NOT the window-palette
/// `brandChampagne` token, so the pill stays legible regardless of the
/// user's WindowTint preference.
@MainActor
public struct PillOverlayView: View {
    @ObservedObject private var model: PillOverlayViewModel

    @Environment(\.colorScheme) private var colorScheme
    /// Live: Settings writes the raw value; the pill re-renders on change.
    @AppStorage(WaveformPalette.userDefaultsKey) private var waveformPaletteRaw = WaveformPalette.default.rawValue

    /// Cancel Card. Not a pill — the panel resizes to this footprint at the
    /// same anchor origin when visibility transitions to `.cancelled`.
    static let cancelCardSize = CGSize(
        width: PersonalScribeTheme.Pill.Width.card,
        height: PersonalScribeTheme.Pill.Height.card
    )

    /// Widest and tallest footprint across all states; decides whether
    /// the pill sits "next to an edge" (see `PillAnchor`).
    static let largestSize: CGSize = [PillStyleMetrics.classic, .mini]
        .flatMap { metrics in
            [
                metrics.idleSize, metrics.idleHoverSize,
                metrics.holdToRecordSize, metrics.recordingSize,
                metrics.recordingHoverSize, metrics.pausedSize,
                metrics.transcribingSize, metrics.downloadingSize,
                metrics.loadingSize, metrics.errorSize,
            ]
        }
        .reduce(cancelCardSize) {
            CGSize(width: max($0.width, $1.width), height: max($0.height, $1.height))
        }

    /// Pure mapping from a `PillOverlayVisibility` case to the panel
    /// footprint the overlay must render at. Used by
    /// `PillOverlayPresenter` (#044) to drive per-state panel resize:
    /// the NSPanel frame matches the visible pill's bounds so clicks
    /// outside the pill don't land on an invisible "halo" of the
    /// fixed-size panel canvas.
    ///
    /// `.hidden` returns `.zero` because nothing is rendered; the
    /// presenter short-circuits to `orderOut` on that case and never
    /// resizes the panel to zero in practice.
    public static func size(
        for visibility: PillVisibilityState,
        style: PillStyle,
        isHovered: Bool = false
    ) -> CGSize {
        let metrics = style.metrics
        switch visibility {
        case .hidden:
            return .zero
        case .idle:
            guard isHovered else { return metrics.idleSize }
            return metrics.idleHoverSize
        case .holdToRecord:
            return metrics.holdToRecordSize
        case .recording:
            return isHovered ? metrics.recordingHoverSize : metrics.recordingSize
        case .paused:
            return metrics.pausedSize
        case .transcribing:
            return metrics.transcribingSize
        case .downloading:
            return metrics.downloadingSize
        case .loading:
            return metrics.loadingSize
        case .error:
            return metrics.errorSize
        case .cancelled:
            return cancelCardSize
        }
    }

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
    private var pausedTextColor: Color {
        colorScheme == .dark
            ? PersonalScribeTheme.Pill.Dark.pausedText
            : PersonalScribeTheme.Pill.Light.pausedText
    }

    public init(model: PillOverlayViewModel) {
        self._model = ObservedObject(wrappedValue: model)
    }

    public var body: some View {
        Group {
            switch model.visibility {
            case .hidden:
                EmptyView()
            case .cancelled:
                CancelCardView(onResume: { [weak model] in
                    model?.resumeCancelledRecording()
                })
            case .idle:
                idlePill
            case .holdToRecord:
                holdToRecordPill
            case .recording:
                recordingPill
            case .paused(let elapsedSeconds):
                pausedPill(elapsedSeconds: elapsedSeconds)
            case .transcribing:
                transcribingPill
            case .downloading(let fraction):
                downloadingPill(fraction: fraction)
            case .loading:
                loadingPill
            case .error(let message):
                errorPill(message: message)
            }
        }
        // Visibility-keyed SwiftUI spring removed as part of #044:
        // AppKit now owns the per-state panel frame tween via
        // `NSPanel.setFrame(_:display:animate:)`, driven by the
        // presenter. Per-content animations (equaliser bars, sine wave
        // decay, spinner rotation) continue to live inside each
        // variant — those don't key on `model.visibility` and are
        // unaffected.
        //
        // ONE visibility-keyed SwiftUI animation is retained on purpose:
        // pill↔CancelCard is a crossfade (scope spec "Cancel Card is not
        // a pill"), not a morph. Keying the opacity transition on the
        // derived `isCancelled` bool means pill↔pill transitions don't
        // trigger any SwiftUI animation (AppKit owns that morph via
        // setFrame animate); only the pill↔cancel flip does.
        .animation(.easeInOut(duration: 0.2), value: model.visibility == .cancelled)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.contentAlignment)
    }

    // MARK: - Idle

    private var idlePill: some View {
        let metrics = model.pillStyle.metrics
        let controlsLayout = PillIdleControlsLayout(
            metrics: metrics,
            showsModeButton: model.showsModeButton
        )
        let size = Self.size(
            for: .idle,
            style: model.pillStyle,
            isHovered: model.isHovered
        )

        return Group {
            if model.isHovered {
                ZStack(alignment: .topLeading) {
                    if model.showsModeButton {
                        Circle()
                            .fill(fgDim.opacity(colorScheme == .dark ? 0.18 : 0.14))
                            .overlay(
                                Image(systemName: "square.grid.2x2")
                                    .font(.system(size: metrics.modeIconSize, weight: .medium))
                                    .foregroundColor(fgDim)
                            )
                            .frame(width: metrics.idleModeDiameter, height: metrics.idleModeDiameter)
                            .position(
                                x: controlsLayout.modeFrame?.midX ?? 0,
                                y: controlsLayout.modeFrame?.midY ?? 0
                            )
                    }

                    Circle()
                        .fill(fg.opacity(0.95))
                        .overlay(
                            PersonalScribeLogoView(
                                color: PersonalScribeTheme.Pill.surface(for: colorScheme)
                            )
                            .frame(width: metrics.recordLogoSize, height: metrics.recordLogoSize)
                        )
                        .frame(
                            width: metrics.idleRecordDiameter,
                            height: metrics.idleRecordDiameter
                        )
                        .position(
                            x: controlsLayout.recordFrame.midX,
                            y: controlsLayout.recordFrame.midY
                        )
                        .help("Start recording")
                }
                .frame(width: size.width, height: size.height)
            } else {
                PersonalScribeLogoView(color: fg.opacity(0.9))
                    .frame(width: metrics.idleLogoSize, height: metrics.idleLogoSize)
            }
        }
        .frame(width: size.width, height: size.height)
        .modifier(PillChrome(borderStyle: .idle))
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
        let metrics = model.pillStyle.metrics

        return EqualizerBarsView(
            audioLevel: model.audioLevel,
            tint: fg,
            barCount: 7
        )
        .frame(width: 120, height: 24)
        .frame(width: metrics.holdToRecordSize.width, height: metrics.holdToRecordSize.height)
        .modifier(PillChrome(borderStyle: .active))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) hold-to-record — release to transcribe")
    }

    // MARK: - Recording (spec §2c)

    private var recordingPill: some View {
        let metrics = model.pillStyle.metrics
        let showsControls = !metrics.controlsOnHover || model.isHovered
        let size = Self.size(
            for: .recording,
            style: model.pillStyle,
            isHovered: model.isHovered
        )

        return HStack(spacing: metrics.recordingSpacing) {
            if showsControls {
                controlGlyph(
                    systemName: "pause.fill",
                    diameter: metrics.controlDiameter
                )
            }

            SineWaveView(
                audioLevel: model.audioLevel,
                decayMode: .animated,
                palette: model.waveformPaletteOverride
                    ?? WaveformPalette(rawValue: waveformPaletteRaw)
                    ?? .default,
                onDarkBackground: colorScheme == .dark,
                renderDate: model.waveformRenderDate
            )
            .frame(
                width: showsControls ? metrics.waveformControlsWidth : metrics.waveformRestWidth,
                height: showsControls
                    ? metrics.waveformControlsHeight
                    : metrics.waveformRestHeight
            )

            if showsControls {
                stopGlyph(diameter: metrics.stopDiameter)
            }
        }
        .padding(.horizontal, metrics.recordingHorizontalInset)
        .frame(width: size.width, height: size.height)
        .modifier(PillChrome(borderStyle: .idle))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) recording — tap to stop")
    }

    private func pausedPill(elapsedSeconds: Int) -> some View {
        let metrics = model.pillStyle.metrics
        let size = Self.size(
            for: .paused(elapsedSeconds: elapsedSeconds),
            style: model.pillStyle
        )

        return HStack(spacing: metrics.pausedSpacing) {
            controlGlyph(
                systemName: "play.fill",
                diameter: metrics.controlDiameter
            )

            Text("Paused · \(Self.elapsedText(elapsedSeconds))")
                .font(.system(size: metrics.pausedFontSize, weight: .semibold))
                .foregroundColor(pausedTextColor)
                .frame(maxWidth: .infinity)

            stopGlyph(diameter: metrics.stopDiameter)
        }
        .padding(.horizontal, metrics.pausedHorizontalInset)
        .frame(width: size.width, height: size.height)
        .modifier(PillChrome(borderStyle: .idle))
        .accessibilityElement()
        .accessibilityLabel("Recording paused at \(Self.elapsedText(elapsedSeconds))")
    }

    private func stopGlyph(diameter: CGFloat) -> some View {
        Circle()
            .fill(fgStop)
            .frame(width: diameter, height: diameter)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.white)
                    .frame(width: diameter * 0.38, height: diameter * 0.38)
            )
    }

    private func controlGlyph(systemName: String, diameter: CGFloat) -> some View {
        Circle()
            .fill(fgDim.opacity(colorScheme == .dark ? 0.18 : 0.14))
            .frame(width: diameter, height: diameter)
            .overlay(
                Image(systemName: systemName)
                    .font(.system(size: diameter * 0.4, weight: .semibold))
                    .foregroundColor(fgDim)
            )
    }

    static func elapsedText(_ elapsedSeconds: Int) -> String {
        let clamped = max(0, elapsedSeconds)
        return "\(clamped / 60):\(String(format: "%02d", clamped % 60))"
    }

    // MARK: - Transcribing (spec §2d)

    private var transcribingPill: some View {
        let metrics = model.pillStyle.metrics

        return ProgressView()
            .controlSize(.small)
            .tint(fg)
        .frame(width: metrics.transcribingSize.width, height: metrics.transcribingSize.height)
        .modifier(PillChrome(borderStyle: .transcribing))
        .accessibilityElement()
        .accessibilityLabel("\(AppBrand.displayName) transcribing")
    }

    // MARK: - Downloading

    private func downloadingPill(fraction: Double) -> some View {
        let percent = Int((fraction * 100).rounded())
        let metrics = model.pillStyle.metrics

        return HStack(spacing: metrics.statusSpacing) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(fg)

            VStack(alignment: .leading, spacing: 2) {
                Text("Downloading model \(percent)%")
                    .font(.system(size: metrics.downloadStatusFontSize, weight: .medium))
                    .foregroundColor(fg)

                ProgressView(value: max(0, min(fraction, 1)))
                    .progressViewStyle(.linear)
                    .tint(fg)
                    .frame(height: 2)
            }
        }
        .padding(.horizontal, metrics.statusHorizontalInset)
        .frame(width: metrics.downloadingSize.width, height: metrics.downloadingSize.height)
        .modifier(PillChrome())
    }

    // MARK: - Loading

    private var loadingPill: some View {
        let metrics = model.pillStyle.metrics

        return HStack(spacing: metrics.statusSpacing) {
            ProgressView()
                .controlSize(.small)
                .tint(fg)

            Text("Warming up model…")
                .font(.system(size: metrics.statusFontSize, weight: .medium))
                .foregroundColor(fg)
        }
        .frame(width: metrics.loadingSize.width, height: metrics.loadingSize.height)
        .modifier(PillChrome())
    }

    // MARK: - Error

    private func errorPill(message: String) -> some View {
        let metrics = model.pillStyle.metrics

        return HStack(spacing: metrics.statusSpacing) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(fgStop)   // red — same stop/error red

            Text(message)
                .font(.system(size: metrics.statusFontSize, weight: .medium))
                .foregroundColor(fg)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, metrics.statusHorizontalInset)
        .frame(width: metrics.errorSize.width, height: metrics.errorSize.height)
        .modifier(PillChrome())
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
/// recording use `.active` (clay 1.5px); transcribing uses its
/// `.transcribing` champagne 40% border.
///
/// ## Fuzzy-edge fix (2026-04-18)
/// NSPanel shadow disabled at the panel layer; `.clipShape` applied
/// BEFORE `.shadow` so the shadow composites on a clean pixel boundary.
private struct PillChrome: ViewModifier {
    let borderStyle: PillBorderStyle
    @Environment(\.colorScheme) private var colorScheme

    init(borderStyle: PillBorderStyle = .idle) {
        self.borderStyle = borderStyle
    }

    func body(content: Content) -> some View {
        let base = PersonalScribeTheme.Pill.surface(for: colorScheme)
        let isLight = colorScheme == .light
        // The idle hairline is white-on-navy; on the cream pill use a
        // dark hairline so the edge stays visible.
        let strokeColor = (isLight && borderStyle == .idle) ? Color.black.opacity(0.1) : borderStyle.strokeColor
        let radius = borderStyle.cornerRadius
        content
            .background {
                RoundedRectangle(
                    cornerRadius: radius,
                    style: .continuous
                )
                // Vertical gradient: top face ~7% brighter than base.
                .fill(base)
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
                // Bevel: light catches the top edge, the bottom edge falls
                // into shade.
                .overlay {
                    RoundedRectangle(
                        cornerRadius: radius,
                        style: .continuous
                    )
                    .strokeBorder(
                        LinearGradient(
                            colors: isLight
                                ? [Color.white.opacity(0.9), Color.black.opacity(0.14)]
                                : [Color.white.opacity(0.22), Color.black.opacity(0.45)],
                            startPoint: .top,
                            endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
                }
                // State-aware border stroke — see `PillBorderStyle`.
                .overlay {
                    RoundedRectangle(
                        cornerRadius: radius,
                        style: .continuous
                    )
                    .stroke(strokeColor, lineWidth: borderStyle.lineWidth)
                }
            }
            .clipShape(
                RoundedRectangle(
                    cornerRadius: borderStyle.cornerRadius,
                    style: .continuous
                )
            )
    }
}

/// Cancel Card — shown when `PillOverlayViewModel.visibility == .cancelled`
/// (pill UX spec §2f). Replaces the pill surface at the same screen
/// anchor. Not a pill — its own cooler-navy background, red border, and
/// right-aligned Resume button.
///
/// Auto-dismiss and Resume are managed by `PillOverlayViewModel`; this
/// view is purely presentational.
@MainActor
struct CancelCardView: View {
    let onResume: @MainActor () -> Void

    var body: some View {
        let textColor = PersonalScribeTheme.Pill.Dark.waveform
        let background = PersonalScribeTheme.Pill.CancelCard.background
        let borderColor = PersonalScribeTheme.Pill.Border.cancelColor
        let borderWidth = PersonalScribeTheme.Pill.Border.cancelWidth
        let undoText = PersonalScribeTheme.Pill.CancelCard.undoText
        let undoFill = PersonalScribeTheme.Pill.CancelCard.undoFill

        HStack(spacing: 12) {
            Text("Recording cancelled")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(textColor)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Button(action: onResume) {
                Text("Resume")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(undoText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(undoFill)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Resume — continue the cancelled recording")
        }
        .padding(.horizontal, 14)
        .frame(
            width: PillOverlayView.cancelCardSize.width,
            height: PillOverlayView.cancelCardSize.height,
            alignment: .leading
        )
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(borderColor, lineWidth: borderWidth)
        )
        .accessibilityElement(children: .combine)
    }
}

#Preview("Cancel Card — default") {
    CancelCardView(onResume: {})
        .padding(40)
        .background(Color.black.opacity(0.3))
        .preferredColorScheme(.dark)
}
