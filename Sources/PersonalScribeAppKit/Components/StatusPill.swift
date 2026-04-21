import SwiftUI

/// A small rounded pill with a coloured dot + label.
///
/// Example: `• Ready`, `• Recording`, `• Link`.
///
/// ## Scope
/// `StatusPill` is consumed by:
/// - `SettingsWindow` (Phase 3)
/// - `OnboardingWindow` (Phase 3)
///
/// It is **not** used in the menu bar (native `NSMenu`, no SwiftUI) or in
/// the pill overlay (which composes `PersonalScribeLogoView` + `WaveformView`
/// directly). See `Component_Inventory.md` row 3.
public struct StatusPill: View {
    public enum Status: Hashable, Sendable {
        case ready
        case recording
        case neutral
        /// Warning / in-flight state (e.g. a model download in progress).
        /// Renders an amber dot — distinguishes "something is happening"
        /// from `.ready` (done) and `.failed` (errored).
        case warning
        /// Failure state (e.g. a model download errored). Reuses the
        /// palette's `statusRecording` red so it reads as a clear error
        /// without introducing a new palette token.
        case failed

        /// The colour to use for the dot. The palette drives the choice
        /// so callers don't need to reason about dark/light variants.
        public func color(for palette: PersonalScribeTheme.Palette) -> Color {
            switch self {
            case .ready: return palette.statusReady
            case .recording: return palette.statusRecording
            case .neutral: return palette.brandChampagne
            case .warning: return Color.orange
            case .failed: return palette.statusRecording
            }
        }
    }

    public let status: Status
    public let label: String

    @Environment(\.colorScheme) private var colorScheme

    public init(status: Status, label: String) {
        self.status = status
        self.label = label
    }

    public var body: some View {
        let palette = PersonalScribeTheme.Palette.for(scheme: colorScheme)
        let dotColor = status.color(for: palette)

        HStack(spacing: PersonalScribeTheme.Components.StatusPill.itemSpacing) {
            Circle()
                .fill(dotColor)
                .frame(
                    width: PersonalScribeTheme.Components.StatusPill.dotSize,
                    height: PersonalScribeTheme.Components.StatusPill.dotSize
                )
            Text(label)
                .font(PersonalScribeTheme.Typography.caption.font)
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, PersonalScribeTheme.Components.StatusPill.horizontalPadding)
        .padding(.vertical, PersonalScribeTheme.Components.StatusPill.verticalPadding)
        .background(
            Capsule()
                .fill(palette.elevatedSurface)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    palette.brandChampagne.opacity(PersonalScribeTheme.Components.StatusPill.borderOpacity),
                    lineWidth: PersonalScribeTheme.Components.StatusPill.borderWidth
                )
        )
        .accessibilityElement()
        .accessibilityLabel("\(label), \(accessibilityStatusPhrase)")
    }

    private var accessibilityStatusPhrase: String {
        switch status {
        case .ready: return "ready"
        case .recording: return "recording"
        case .neutral: return "idle"
        case .warning: return "in progress"
        case .failed: return "failed"
        }
    }
}

#Preview("StatusPill — variants") {
    VStack(spacing: PersonalScribeTheme.Components.Preview.stackSpacing) {
        StatusPill(status: .ready, label: "Ready")
        StatusPill(status: .recording, label: "Recording")
        StatusPill(status: .neutral, label: "Idle")
    }
    .padding(PersonalScribeTheme.Components.Preview.canvasPadding)
    .background(PersonalScribeTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
