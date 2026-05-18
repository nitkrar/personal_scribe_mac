import Foundation

/// Batch ASR transcriber surface introduced in #078. Composes
/// `ModelLifecycle` (per L13) and exposes the role-specific batch
/// `transcribe(_:)` plus a `capabilities` accessor (per L11) that
/// declares which optional `TranscriptionResult` metadata the
/// adapter populates.
///
/// Conformers: `FluidAudioParakeetTranscriberAdapter` and
/// `FluidAudioQwenTranscriberAdapter` in `PersonalScribeTranscription`.
public protocol Transcriber: ModelLifecycle, Sendable {
    /// What this transcriber surfaces on the optional metadata
    /// fields of `TranscriptionResult`. Features query this before
    /// exposing UI that depends on per-token timings or confidence.
    var capabilities: TranscriberCapabilities { get }

    /// Run a single batch transcription pass. Implementations are
    /// expected to have completed `prepare()` before being called.
    /// Errors propagate as `PersonalScribeError` per the legacy
    /// protocol's runtime convention.
    func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult
}

public extension Transcriber {
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try await transcribe(audio, languageHint: nil)
    }
}
