import SwiftUI

/// Standardised primary / secondary action button.
///
/// * `.primary` — champagne fill, dark text. The "Continue" / "Save"
///   button used across onboarding + settings.
/// * `.secondary` — surface fill, primary-text colour. Used for
///   "Cancel" / "Later" actions.
///
/// Consumers: `OnboardingWindow`, `SettingsWindow` (both Phase 3).
public struct ActionButton: View {
    public enum Variant: Hashable, Sendable {
        case primary
        case secondary
    }

    public let title: String
    public let variant: Variant
    public let isEnabled: Bool
    public let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    public init(
        title: String,
        variant: Variant = .primary,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.variant = variant
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        Button(action: action) {
            Text(title)
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(foreground(palette: palette))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(minWidth: 92)
                .background(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .fill(background(palette: palette))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .strokeBorder(border(palette: palette), lineWidth: 0.5)
                )
                .opacity(isEnabled ? 1.0 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }

    private func foreground(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .primary:
            // Contrast against champagne fill — use the dark-scheme
            // app-background colour so it reads correctly on both
            // themes.
            return SeshatTheme.Palette.dark.appBackground
        case .secondary:
            return palette.primaryText
        }
    }

    private func background(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .primary: return palette.brandChampagne
        case .secondary: return palette.elevatedSurface
        }
    }

    private func border(palette: SeshatTheme.Palette) -> Color {
        switch variant {
        case .primary: return palette.brandChampagne.opacity(0.6)
        case .secondary: return palette.brandChampagne.opacity(0.2)
        }
    }
}

#Preview("ActionButton — variants") {
    VStack(spacing: 10) {
        ActionButton(title: "Continue") { }
        ActionButton(title: "Cancel", variant: .secondary) { }
        ActionButton(title: "Disabled", isEnabled: false) { }
    }
    .padding(24)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
