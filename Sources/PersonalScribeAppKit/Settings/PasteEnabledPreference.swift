import Foundation

/// Master toggle for "paste result text" — when `false`, the app does
/// NOT paste the transcription into the frontmost text field AND does
/// NOT write it to the clipboard. When `true`, the existing `PasteMode`
/// picker determines *how* paste is delivered (paste-at-cursor vs
/// clipboard-only).
///
/// Persisted under `UserDefaults` key `"PasteEnabled"` (unprefixed —
/// bundle-scoped already). Default `true` so existing behaviour is
/// preserved until a user explicitly disables it.
///
/// Storage shape mirrors `ShowInDockPreference` — namespace with static
/// `resolve(from:)` + `persist(_:to:)` using `object(forKey:)` to
/// distinguish unset from explicit-false.
///
/// Reference: `plans/App UI design/final_settings_general_v2.png`
/// TEXT INPUT section. Settings UI landed in mockup-gaps D.3
/// (2026-04-21); the downstream wiring to `OutputService` (so the
/// master toggle actually suppresses delivery) is deferred — tracked
/// in `plans/backlog/ui-mockup-gaps.md`.
public enum PasteEnabledPreference {
    /// UserDefaults key. Unprefixed by design — bundle-scoped already.
    public static let userDefaultsKey = "PasteEnabled"

    /// Default — paste delivery is on for a fresh install.
    public static let `default`: Bool = true

    /// Reads the persisted preference, falling back to `default` when
    /// the key is absent. `object(forKey:)` probed first so
    /// "explicitly false" is distinct from "not set".
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
