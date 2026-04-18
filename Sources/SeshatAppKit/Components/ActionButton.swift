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

        func foregroundColor(for palette: SeshatTheme.Palette) -> Color {
            switch self {
            case .primary:
                // Contrast against champagne fill — use the dark-scheme
                // app-background colour so it reads correctly on both
                // themes.
                return SeshatTheme.Palette.dark.appBackground
            case .secondary:
                return palette.primaryText
            }
        }

        func backgroundColor(for palette: SeshatTheme.Palette) -> Color {
            switch self {
            case .primary: return palette.brandChampagne
            case .secondary: return palette.elevatedSurface
            }
        }

        func borderColor(for palette: SeshatTheme.Palette) -> Color {
            switch self {
            case .primary:
                return palette.brandChampagne.opacity(
                    SeshatTheme.Components.ActionButton.primaryBorderOpacity
                )
            case .secondary:
                return palette.brandChampagne.opacity(
                    SeshatTheme.Components.ActionButton.secondaryBorderOpacity
                )
            }
        }
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

    internal var effectiveOpacity: Double {
        isEnabled ? 1.0 : SeshatTheme.Components.ActionButton.disabledOpacity
    }

    public var body: some View {
        let palette = SeshatTheme.Palette.for(scheme: colorScheme)

        Button(action: action) {
            Text(title)
                .font(SeshatTheme.Typography.body.font.weight(.semibold))
                .foregroundStyle(variant.foregroundColor(for: palette))
                .padding(.horizontal, SeshatTheme.Components.ActionButton.horizontalPadding)
                .padding(.vertical, SeshatTheme.Components.ActionButton.verticalPadding)
                .frame(minWidth: SeshatTheme.Components.ActionButton.minimumWidth)
                .background(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .fill(variant.backgroundColor(for: palette))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SeshatTheme.Radius.row, style: .continuous)
                        .strokeBorder(
                            variant.borderColor(for: palette),
                            lineWidth: SeshatTheme.Components.ActionButton.borderWidth
                        )
                )
                .opacity(effectiveOpacity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

#Preview("ActionButton — variants") {
    VStack(spacing: SeshatTheme.Components.Preview.stackSpacing) {
        ActionButton(title: "Continue") { }
        ActionButton(title: "Cancel", variant: .secondary) { }
        ActionButton(title: "Disabled", isEnabled: false) { }
    }
    .padding(SeshatTheme.Components.Preview.canvasPadding)
    .background(SeshatTheme.Palette.dark.appBackground)
    .preferredColorScheme(.dark)
}
