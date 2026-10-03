import AppKit
import PersonalScribeCore

/// User-selectable floating-pill appearance, independent of the system
/// theme and of `WindowTint`.
///
/// Three variants:
/// * `.dark`   — always dark-aqua (default).
/// * `.light`  — always light-aqua.
/// * `.system` — inherit from the system (follows light/dark mode).
///
/// Default is `.dark` because the floating pill is most legible on a
/// dark-navy surface regardless of the surrounding window's appearance.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §1
/// and the `SeshatTheme.swift` drop-in (`PillAppearance` adopted
/// verbatim; type is namespace-free per the project naming rule).
public enum PillAppearance: String, CaseIterable, Identifiable, Codable, Sendable, StoredPreference {
    case dark   = "Dark"
    case light  = "Light"
    case system = "System"

    public var id: String { rawValue }

    public static let setting = SettingKey<PillAppearance>(key: "PillAppearance", default: .dark)

    public func persist(to defaults: UserDefaults = .standard) {
        Self.persist(self, to: defaults)
    }

    /// Resolves whether the pill should render with dark tokens.
    /// `.dark` → always true; `.light` → always false; `.system` →
    /// follows the caller-supplied `systemIsDark` flag.
    public func effectiveIsDark(systemIsDark: Bool) -> Bool {
        switch self {
        case .dark:   return true
        case .light:  return false
        case .system: return systemIsDark
        }
    }

    /// NSAppearance to apply to the pill NSPanel.
    /// Returns `nil` for `.system` so the panel inherits.
    public func nsAppearance(systemIsDark: Bool) -> NSAppearance? {
        _ = systemIsDark
        switch self {
        case .dark:   return NSAppearance(named: .darkAqua)
        case .light:  return NSAppearance(named: .aqua)
        case .system: return nil
        }
    }
}
