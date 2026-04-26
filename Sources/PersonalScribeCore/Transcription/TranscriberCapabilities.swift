import Foundation

/// What a `Transcriber2` (or `StreamingTranscriber`) advertises about
/// the optional metadata it can populate on a `TranscriptionResult`.
///
/// Per #078 L11 + synthesis decision #1: features that depend on
/// optional metadata (token timings, confidence numbers, performance
/// metrics, custom-vocabulary CTC marker arrays) query an adapter's
/// capabilities **before** exposing the corresponding UI. Today's
/// Parakeet adapter populates all four; Qwen3's plain-`String` shape
/// populates none.
///
/// Speaker turns are deliberately NOT a capability here — they belong
/// on `SpeakerDiarizer`, not on a transcriber. (See L9: three role
/// protocols, no polymorphic unification.)
public struct TranscriberCapabilities: Sendable, Equatable {
    /// Adapter populates `TranscriptionResult.tokenTimings` with
    /// per-token start/end/confidence triples when present.
    public let providesTokenTimings: Bool

    /// Adapter populates `TranscriptionResult.confidence` with an
    /// overall scalar score.
    public let providesConfidence: Bool

    /// Adapter populates `TranscriptionResult.performanceMetrics`
    /// with timing measurements (load, encode, decode wall-clock).
    public let providesPerformanceMetrics: Bool

    /// Adapter accepts a custom-vocabulary list and populates the
    /// CTC detection / application arrays on `TranscriptionResult`.
    public let providesCustomVocabulary: Bool

    public init(
        providesTokenTimings: Bool = false,
        providesConfidence: Bool = false,
        providesPerformanceMetrics: Bool = false,
        providesCustomVocabulary: Bool = false
    ) {
        self.providesTokenTimings = providesTokenTimings
        self.providesConfidence = providesConfidence
        self.providesPerformanceMetrics = providesPerformanceMetrics
        self.providesCustomVocabulary = providesCustomVocabulary
    }
}
