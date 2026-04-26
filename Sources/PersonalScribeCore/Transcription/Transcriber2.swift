import Foundation

/// Batch ASR transcriber surface introduced in #078. Composes
/// `ModelLifecycle` (per L13) and exposes the role-specific batch
/// `transcribe(_:)` plus a `capabilities` accessor (per L11) that
/// declares which optional `TranscriptionResult` metadata the
/// adapter populates.
///
/// Naming: the `2` suffix is **temporary**. This protocol lands
/// alongside today's legacy `Transcriber` (Sources/PersonalScribeCore/
/// Protocols.swift) so trunk stays buildable through the parallel-
/// build phase. At Phase G cutover (#078.30a) the legacy `Transcriber`
/// is renamed to `LegacyTranscriber` and `Transcriber2` is renamed to
/// `Transcriber`.
///
/// Conformers in #078: `FluidAudioParakeetTranscriberAdapter` and
/// `FluidAudioQwenTranscriberAdapter` (Phase D).
public protocol Transcriber2: ModelLifecycle, Sendable {
    /// What this transcriber surfaces on the optional metadata
    /// fields of `TranscriptionResult`. Features query this before
    /// exposing UI that depends on per-token timings or confidence.
    var capabilities: TranscriberCapabilities { get }

    /// Run a single batch transcription pass. Implementations are
    /// expected to have completed `prepare()` before being called.
    /// Errors propagate as `PersonalScribeError` per the legacy
    /// protocol's runtime convention.
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
}
