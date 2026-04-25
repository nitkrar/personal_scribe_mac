import Foundation

/// User-selectable pill *shape* preference — independent of
/// `PillAppearance` (dark/light tokens) and `PillVisibility`
/// (when the pill is shown at all).
///
/// Three variants:
/// * `.classic` — full pill with voice-modulated waveform (default).
/// * `.mini`    — compact flat pill, no inline content.
/// * `.none`    — pill hidden regardless of `PillVisibility`.
///
/// Persisted under `UserDefaults` key `"PillStyle"` (unprefixed —
/// bundle-scoped already, per the project's
/// `PreferenceMigrator`-codified UserDefaults key policy).
///
/// Reference: `plans/App UI design/final_settings_general_v2.png`
/// RECORDING WINDOW section. The Settings UI that sets this
/// preference landed in mockup-gaps D.1 (2026-04-21); the downstream
/// wiring to `PillOverlayView` rendering is deferred — tracked in
/// `plans/backlog/ui-mockup-gaps.md`.
public enum PillStyle: String, CaseIterable, Identifiable, Sendable {
    case classic = "Classic"
    case mini    = "Mini"
    case none    = "None"

    public var id: String { rawValue }

    /// UserDefaults key. Unprefixed by design — bundle-scoped already.
    public static let userDefaultsKey = "PillStyle"

    /// Reads the persisted style, falling back to `.classic` when
    /// absent or the stored value is not a recognised case.
    public static func resolve(from defaults: UserDefaults = .standard) -> PillStyle {
        guard let raw = defaults.string(forKey: userDefaultsKey),
              let value = PillStyle(rawValue: raw) else {
            return .classic
        }
        return value
    }

    /// Writes the style's raw value to defaults.
    public func persist(to defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.userDefaultsKey)
    }
}
