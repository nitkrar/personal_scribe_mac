import Foundation

/// Gates the synthetic `Cmd+V` post in `ClipboardBatchOutput.deliverBatch`.
/// When `true`, the transcript is written to the clipboard AND auto-pasted
/// into the frontmost text surface (subject to the remaining #042 gates:
/// AX permission + focus-externality probe). When `false`, the transcript
/// is copied to the clipboard only — no `Cmd+V` is posted, and the user
/// pastes manually.
///
/// Replaces the pre-#072 split of `PasteEnabledPreference` (master "paste
/// result text" toggle, unwired) and `PasteMode` (paste-at-cursor vs
/// clipboard-only picker). One boolean captures the same two-state space
/// the picker did without the redundant master.
///
/// Persisted under `UserDefaults` key `"AutoPasteEnabled"`. Default
/// `true` — preserves pre-#072 paste-at-cursor behavior for fresh
/// installs. `object(forKey:)` probe distinguishes unset from explicit
/// false, matching `BackgroundLaunchPreference`'s pattern.
public enum AutoPasteEnabledPreference {
    public static let userDefaultsKey = "AutoPasteEnabled"

    public static let `default`: Bool = true

    public static func resolve(from defaults: UserDefaults = .standard) -> Bool {
        guard defaults.object(forKey: userDefaultsKey) != nil else {
            return `default`
        }
        return defaults.bool(forKey: userDefaultsKey)
    }

    public static func persist(_ value: Bool, to defaults: UserDefaults = .standard) {
        defaults.set(value, forKey: userDefaultsKey)
    }
}
