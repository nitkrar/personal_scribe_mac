import Foundation

/// Events a `SpeakerDiarizer` emits. Update-oriented shape per L10 —
/// matches FluidAudio's streaming `Diarizer` protocol so streaming
/// adapters (LSEEND / Sortformer, separate ticket) and offline
/// adapters (`OfflineDiarizerManager` via the degenerate-streaming
/// case) share one event type.
///
/// `.update` carries provisional + finalized turns separately:
///   - `provisional`: turns whose boundaries may still revise; the
///     fusion processor (`DiarizedTurnTranscriptionProcessor`,
///     #078.23) does NOT trigger ASR for these per L26.
///   - `finalized`: turn boundaries are stable; fusion ASRs each.
///
/// `.terminal` arrives once when the stream ends (or when the offline
/// degenerate adapter completes its single `process(audio:)` call).
public enum SpeakerDiarizationEvent: Sendable, Equatable {
    case update(provisional: [SpeakerTurn], finalized: [SpeakerTurn])
    case terminal([SpeakerTurn])
    /// Adapter encountered an unrecoverable error during diarization
    /// (model crash, config validation failure, runtime exception).
    /// The fusion processor (`DiarizedTurnTranscriptionProcessor`)
    /// observes this and rethrows so the orchestrator can surface the
    /// failure to the UI instead of producing a silent empty transcript.
    /// `reason` is a human-readable description (e.g.
    /// `String(describing: error)`); kept as `String` so the event
    /// stays `Equatable` and `Sendable` without leaking the underlying
    /// `Error` type into the protocol.
    case failed(reason: String)
}
