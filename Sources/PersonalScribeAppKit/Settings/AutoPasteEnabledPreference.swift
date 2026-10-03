import Foundation
import PersonalScribeCore

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
/// Default `true` preserves paste-at-cursor for fresh installs.
public enum AutoPasteEnabledPreference: StoredPreference {
    public static let setting = PreferenceKeys.autoPasteEnabled
}
