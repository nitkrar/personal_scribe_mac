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

        HStack(spacing: SeshatTheme.Components.StatusPill.itemSpacing) {
            Circle()
                .fill(dotColor)
                .frame(
                    width: SeshatTheme.Components.StatusPill.dotSize,
                    height: SeshatTheme.Components.StatusPill.dotSize
                )
            Text(label)
                .font(SeshatTheme.Typography.caption.font)
                .foregroundStyle(palette.primaryText)
        }
        .padding(.horizontal, SeshatTheme.Components.StatusPill.horizontalPadding)
        .padding(.vertical, SeshatTheme.Components.StatusPill.verticalPadding)
        .background(
            Capsule()
                .fill(palette.elevatedSurface)
        )
        .overlay(
            Capsule()
                .strokeBorder(
                    palette.brandChampagne.opacity(SeshatTheme.Components.StatusPill.borderOpacity),
                    lineWidth: SeshatTheme.Components.StatusPill.borderWidth
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
        }
    }
}

#Preview("StatusPill — variants") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        StatusPill(status: .ready, label: "Ready")
        StatusPill(status: .recording, label: "Recording")
        StatusPill(status: .neutral, label: "Idle")
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
