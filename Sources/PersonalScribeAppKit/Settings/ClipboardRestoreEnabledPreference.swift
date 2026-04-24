import Foundation

/// Gates the scheduled restore of the user's pre-transcript clipboard
/// in `ClipboardBatchOutput.deliverBatch`. When `true`, the service
/// schedules an `restoreSnapshotIfUnchanged` after
/// `ClipboardRestoreDelay` seconds; when `false`, no restore is
/// scheduled and the transcript remains on the clipboard until the user
/// (or another app) writes something new.
///
/// Orthogonal to `AutoPasteEnabledPreference` by design — restore
/// controls "how long does the transcript stay on the clipboard",
/// auto-paste controls "do we try to land it in the focused field".
/// Both dimensions are independent: a user can set auto-paste OFF +
/// restore ON to mean "copy to clipboard for N seconds, then revert" and
/// auto-paste ON + restore OFF to mean "paste and leave the transcript
/// on the clipboard for unlimited Cmd+V re-paste".
///
/// Persisted under `UserDefaults` key `"ClipboardRestoreEnabled"`.
/// Default `false` — fresh installs leave the transcript on the clipboard
/// indefinitely, which structurally prevents #072's silent-drop-into-
/// cursorless-surface symptom. Users who value the
/// "preserve pre-recording clipboard" convenience opt in.
///
/// `object(forKey:)` probe distinguishes unset from explicit false,
/// matching `AutoPasteEnabledPreference` / `BackgroundModePreference`.
public enum ClipboardRestoreEnabledPreference {
    public static let userDefaultsKey = "ClipboardRestoreEnabled"

    public static let `default`: Bool = false

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
