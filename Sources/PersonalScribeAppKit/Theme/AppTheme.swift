import AppKit
import SwiftUI
import PersonalScribeCore

/// User-selectable app-level master theme.
///
/// Three variants:
/// * `.light`  — forces the light scheme (default).
/// * `.dark`   — forces the dark scheme.
/// * `.system` — follows the macOS system appearance.
///
/// `AppTheme` is the single source of truth for "light vs dark" —
/// `WindowTint` (Warm / Neutral) is a light-mode-only brand flavor and
/// no longer carries a `.dark` case. `PillAppearance` remains
/// independent: the floating pill's own appearance picker is not
/// affected by `AppTheme`.
///
/// Introduced by mockup-gaps G (2026-04-21) to replace the previous
/// `WindowTint.dark` double-duty behaviour. There is no migration
/// shim: a persisted `"WindowTint" == "Dark"` silently falls back to
/// `WindowTint.warm` via `WindowTint.resolve`.
public enum AppTheme: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case light  = "Light"
    case dark   = "Dark"
    case system = "System"

    public var id: String { rawValue }

    /// Light was a product decision, not a system-follows default.
    public static let setting = SettingKey<AppTheme>(key: "AppTheme", default: .light)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }

    /// Effective SwiftUI `ColorScheme` for this theme, resolved
    /// against the supplied system state.
    ///
    /// * `.light`  → `.light` regardless of system.
    /// * `.dark`   → `.dark`  regardless of system.
    /// * `.system` → mirrors `systemIsDark`.
    public func effectiveScheme(systemIsDark: Bool) -> ColorScheme {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return systemIsDark ? .dark : .light
        }
    }

    /// `NSAppearance` to apply to windows owned by the app.
    ///
    /// * `.light`  → aqua (applied regardless of system).
    /// * `.dark`   → darkAqua (applied regardless of system).
    /// * `.system` → `nil` so macOS resolves from the system setting.
    public func nsAppearance(systemIsDark: Bool) -> NSAppearance? {
        _ = systemIsDark
        switch self {
        case .light:  return NSAppearance(named: .aqua)
        case .dark:   return NSAppearance(named: .darkAqua)
        case .system: return nil
        }
    }
}
