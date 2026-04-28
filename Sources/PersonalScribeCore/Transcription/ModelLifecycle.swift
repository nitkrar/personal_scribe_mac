import Foundation

/// Lifecycle methods shared by every model-bound runtime piece — ASR
/// transcribers, streaming transcribers, speaker diarizers, and any
/// future processor that loads a model from disk.
///
/// Per #078 L3 / L13: this protocol exists so the three role-specific
/// output protocols (`Transcriber`, `StreamingTranscriber`,
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
    /// Ensures the bound descriptor's model artifacts are present on
    /// disk. Idempotent — no-op if files are already there.
    ///
    /// Distinct from `prepare()`: this method **must not** instantiate
    /// the runtime manager, load weights into memory, or perform CoreML
    /// compilation that persists state. It populates disk and exits.
    ///
    /// Use cases:
    /// - The AI Models tab "Download" button: pull files without
    ///   incurring the RAM tax of a loaded manager that the user may
    ///   never activate.
    /// - As a precondition inside `prepare()`: load needs files on disk
    ///   first; `prepare` ensures download then loads.
    ///
    /// Progress flows through `modelDownloadProgress()`, the same hot
    /// stream `prepare()` uses.
    func downloadIfNeeded() async throws

    /// Loads model weights and brings the runtime into a state where
    /// the role-specific entry point (e.g. `transcribe(_:)`) can be
    /// called. Idempotent — calling twice must not reload or re-fetch.
    /// Implementations should call `downloadIfNeeded()` first so a load
    /// from a missing disk state still succeeds end-to-end.
    func prepare() async throws

    /// Hot stream of model-download progress for the bound descriptor.
    /// Conformers that have nothing to download (e.g. once `prepare`
    /// has loaded local weights) return a stream that immediately
    /// publishes a `.finished` phase and terminates.
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>

    /// Explicit teardown hook used when a model is evicted from the
    /// provider cache but the adapter may still be retained elsewhere.
    /// Implementations should release heavyweight runtime state
    /// (loaded CoreML models, decoder caches, auxiliary managers)
    /// without relying on `deinit`.
    func cleanup() async
}

public extension ModelLifecycle {
    /// Backstop default — falls back to `prepare()` for callers that
    /// haven't yet split download from load. Each adapter overrides
    /// this with a disk-only implementation (FluidAudio's `download`
    /// or `DownloadUtils.downloadRepo`) so the AI Models "Download"
    /// button doesn't load the model into RAM.
    ///
    /// Once every adapter overrides, this default becomes unreachable
    /// and can be removed.
    func downloadIfNeeded() async throws {
        try await prepare()
    }

    /// Default backstop for lightweight or pure-value conformers that
    /// have no retained runtime state to release on eviction.
    func cleanup() async {}
}
