import Foundation

/// Lifecycle methods shared by every model-bound runtime piece — ASR
/// transcribers, streaming transcribers, speaker diarizers, and any
/// future processor that loads a model from disk.
///
/// Per #078 L3 / L13: this protocol exists so the three role-specific
/// output protocols (`Transcriber2`, `StreamingTranscriber`,
/// `SpeakerDiarizer`) can compose `prepare()` and
/// `modelDownloadProgress()` without each redeclaring them. The
/// `ModelBoundProcessorProvider` (#078 L7 / L24) routes
/// `download` / `isDownloaded` / `removeDownloadedFiles` through this
/// single lifecycle path so cache eviction stays correct regardless of
/// which adapter type is bound to a descriptor.
///
/// Today's legacy `Transcriber` protocol (Sources/PersonalScribeCore/
/// Protocols.swift) bundles these methods inline and is left untouched
/// during the parallel-build phase — at Phase G cutover the rename
/// retires the legacy shape.
public protocol ModelLifecycle: Sendable {
    /// Loads model weights and brings the runtime into a state where
    /// the role-specific entry point (e.g. `transcribe(_:)`) can be
    /// called. Idempotent — calling twice must not reload or re-fetch.
    func prepare() async throws

    /// Hot stream of model-download progress for the bound descriptor.
    /// Conformers that have nothing to download (e.g. once `prepare`
    /// has loaded local weights) return a stream that immediately
    /// publishes a `.finished` phase and terminates.
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
}
