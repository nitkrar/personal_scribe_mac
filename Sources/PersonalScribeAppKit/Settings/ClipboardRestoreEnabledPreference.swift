import Foundation
import PersonalScribeCore

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
/// Default `false` keeps the transcript on the clipboard, so a paste
/// into a cursorless surface isn't lost (#072).
public enum ClipboardRestoreEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.clipboardRestoreEnabled
}
