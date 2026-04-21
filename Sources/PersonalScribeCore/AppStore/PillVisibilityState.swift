public enum PillVisibilityState: Sendable, Equatable {
    case hidden
    case idle
    case downloading(fractionCompleted: Double)
    case loading
    /// opt+/ held down, microphone capturing, not yet committed. Release
    /// of the modifier exits directly to `.transcribing` (short-dictation
    /// path — see pill UX spec §3 "hold-to-record for short
    /// transcriptions"). Visuals are the 7-bar equaliser introduced in
    /// Phase 2; Phase 1 reuses the recording-pill chrome as a placeholder.
    case holdToRecord
    case recording
    case transcribing
    case done
    /// Recording was discarded without transcribing (✕ button or Esc).
    /// The pill panel is replaced at the same screen anchor by the
    /// Cancel Card (Phase 3) with an Undo affordance. Clipboard is
    /// restored to its pre-session contents if Undo is invoked.
    case cancelled
    case error(message: String)
}
