import Foundation

/// Wall-clock timing measurements a transcriber may surface when it
/// advertises `TranscriberCapabilities.providesPerformanceMetrics`.
/// Used by Settings and dev-only diagnostics; never used for routing
/// or product behavior.
public struct TranscriberPerformanceMetrics: Sendable, Equatable {
    /// Time spent loading the model into memory on first use, if the
    /// adapter measures it. Reload-on-warm-cache is `.zero`.
    public let loadDuration: Duration?

    /// Time spent in the encoder (audio → acoustic features).
    public let encodeDuration: Duration?

    /// Time spent in the decoder (features → tokens / text).
    public let decodeDuration: Duration?

    /// Total wall-clock time for the transcribe call from input to
    /// returned `TranscriptionResult`. Distinct from
    /// `TranscriptionResult.processingDuration` which the orchestrator
    /// already records — this is the adapter's internal view.
    public let totalDuration: Duration?

    public init(
        loadDuration: Duration? = nil,
        encodeDuration: Duration? = nil,
        decodeDuration: Duration? = nil,
        totalDuration: Duration? = nil
    ) {
        self.loadDuration = loadDuration
        self.encodeDuration = encodeDuration
        self.decodeDuration = decodeDuration
        self.totalDuration = totalDuration
    }
}
