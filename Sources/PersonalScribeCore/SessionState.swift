public enum SessionState: Sendable, Equatable {
    case idle
    case capturing
    /// Audio is being captured under a live hold-to-record gesture. Distinct
    /// from `.capturing` so the store can derive the `.holdToRecord` pill
    /// visibility without a side-channel push from the hotkey layer, and so
    /// release of the gesture can transition directly to `.transcribing`
    /// through the normal state machine. See `#071`.
    case holdRecording
    case transcribing
    case completed
    /// Non-error terminal state: the pipeline exited early without producing
    /// a transcription (e.g. the recording was too short to be worth
    /// transcribing). Distinct from `.error` — real errors (permission,
    /// model, transcription failures) still use `.error`. Display-mapped to
    /// `.idle` so entry points accept it as startable without special-casing
    /// `.error` recovery. See `#075`.
    case shortExit
    case error(PersonalScribeError)
}
