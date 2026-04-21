import SwiftUI

/// Scheme-aware chrome surfaces for the unified window shell.
///
/// `WindowTint` is a light-mode-only brand flavor (post mockup-gaps G —
/// the `.dark` case was dropped). Binding the sidebar background,
/// detail backdrop, brand-header text, and sidebar separator directly
/// to `WindowTint.*` leaked light-only cream/near-black colors into
/// dark theme, producing the half-light / half-dark shell captured in
/// backlog #040.
///
/// Call from `UnifiedWindowView` with the live
/// `@Environment(\.colorScheme)` and the configured `WindowTint`. The
/// helpers return `PersonalScribeTheme.Palette.dark` tokens in dark
/// mode (where the tint is also hidden from Settings UI per G.4) and
/// the `WindowTint` flavor colors in light mode.
///
/// `chromeText` returns the base color only — callers apply their own
/// `.opacity(…)` on top, mirroring the existing `windowTint.primaryText`
/// usage pattern in the view.
enum UnifiedWindowChrome {
    /// Sidebar column background.
    static func sidebarBackground(scheme: ColorScheme, tint: WindowTint) -> Color {
        switch scheme {
        case .dark:
            return PersonalScribeTheme.Palette.dark.surface
        default:
            return tint.secondaryBackground
        }
    }

    /// Detail pane backdrop (behind tab content).
    static func detailBackground(scheme: ColorScheme, tint: WindowTint) -> Color {
        switch scheme {
        case .dark:
            return PersonalScribeTheme.Palette.dark.appBackground
        default:
            return tint.primaryBackground
        }
    }

    /// Base chrome text color (sidebar brand header + footers).
    /// Callers apply their own `.opacity(…)` as needed.
    static func chromeText(scheme: ColorScheme, tint: WindowTint) -> Color {
        switch scheme {
        case .dark:
            return PersonalScribeTheme.Palette.dark.primaryTextBase
        default:
            return tint.primaryText
        }
    }

    /// 1pt sidebar/detail divider — chrome text at 8% alpha.
    static func chromeSeparator(scheme: ColorScheme, tint: WindowTint) -> Color {
        chromeText(scheme: scheme, tint: tint).opacity(0.08)
    }
}
