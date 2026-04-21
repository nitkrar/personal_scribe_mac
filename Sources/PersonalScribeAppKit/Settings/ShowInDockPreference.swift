import Foundation

/// User-selectable "Show in Dock" preference. When `true`, the app
/// presents a Dock icon (`.regular` activation policy); when `false`,
/// the app runs as a menu-bar / floating-pill-only LSUIElement-style
/// process (`.accessory` activation policy).
///
/// Persisted under `UserDefaults` key `"ShowInDock"` (unprefixed —
/// bundle-scoped already, per the project's `PreferenceMigrator`
/// UserDefaults key policy). Default is `true` so new installs see the
/// Dock icon; users can opt out to reclaim Dock real estate.
///
/// Storage shape mirrors `PillAppearance` / `PillStyle`: a namespace
/// with a static `userDefaultsKey` + `resolve(from:)` + `persist(_:to:)`.
/// The underlying value is a plain `Bool` rather than an enum; using a
/// namespace enum instead of free functions keeps the API aligned with
/// the other preference types (`PillAppearance.resolve(from:)`,
/// `PillStyle.resolve(from:)`) and discoverable via autocomplete.
///
/// Reference: `plans/App UI design/final_settings_general_v2.png`
/// APPLICATION section. Settings UI landed in mockup-gaps D.2
/// (2026-04-21); the activation-policy switch is applied at the call
/// site in `GeneralTabViewModel.setShowInDock`.
public enum ShowInDockPreference {
    /// UserDefaults key. Unprefixed by design — bundle-scoped already.
    public static let userDefaultsKey = "ShowInDock"

    /// Default — the Dock icon is visible on a fresh install.
    public static let `default`: Bool = true

    /// Reads the persisted preference, falling back to `default` when
    /// the key is absent. `UserDefaults.bool(forKey:)` returns `false`
    /// on absence so we probe with `object(forKey:)` first to
    /// distinguish "explicitly false" from "not set".
    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    /// Writes the bool to defaults under `userDefaultsKey`.
    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}
