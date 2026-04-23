public enum SessionState: Sendable, Equatable {
    case idle
    case recording
    /// Audio is being captured under a live hold-to-record gesture. Distinct
    /// from `.recording` so the store can derive the `.holdToRecord` pill
    /// visibility without a side-channel push from the hotkey layer, and so
    /// release of the gesture can transition directly to `.transcribing`
    /// through the normal state machine. See `#071`.
    case holdRecording
    case transcribing
    case completed
    case error(PersonalScribeError)
}
