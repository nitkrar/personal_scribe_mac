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
/// the pill overlay (which composes `SeshatLogoView` + `WaveformView`
/// directly). See `Component_Inventory.md` row 3.
public struct StatusPill: View {
    public enum Status: Hashable, Sendable {
        case ready
        case recording
        case neutral

        /// The colour to use for the dot. The palette drives the choice
        /// so callers don't need to reason about dark/light variants.
        public func color(for palette: SeshatTheme.Palette) -> Color {
            switch self {
            case .ready: return palette.statusReady
            case .recording: return palette.statusRecording
            case .neutral: return palette.brandChampagne
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
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)
        let dotColor = status.color(for: palette)

        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
            Text(label)
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, SeshatTheme.Spacing.iconPadding + 2)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(palette.elevatedSurface)
        )
        .overlay(
            Capsule()
                .strokeBorder(palette.brandChampagne.opacity(0.15), lineWidth: 0.5)
        )
        .accessibilityElement()
        .accessibilityLabel("\(label), \(accessibilityStatusPhrase)")
    }

    private var accessibilityStatusPhrase: String {
        switch status {
        case .ready: return "ready"
        case .recording: return "recording"
        case .neutral: return "idle"
        }
    }
}

#Preview("StatusPill — variants") {
    VStack(spacing: 10) {
        StatusPill(status: .ready, label: "Ready")
        StatusPill(status: .recording, label: "Recording")
        StatusPill(status: .neutral, label: "Idle")
    }
    .padding(24)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
