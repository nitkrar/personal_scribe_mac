import Foundation

/// Event surfaced by a VAD boundary session.
public enum VadEvent: Sendable, Equatable {
    case speechEnded
    case speechResumed
}

/// Type-erased handle to a per-session VAD boundary runtime.
public struct VadSessionHandle: Sendable {
    public let ingest: @Sendable ([Float]) async -> VadEvent?

    public init(ingest: @escaping @Sendable ([Float]) async -> VadEvent?) {
        self.ingest = ingest
    }
}

/// Async factory for a per-session VAD boundary handle.
public typealias VadBoundarySessionFactory =
    @Sendable (_ silenceThresholdSeconds: Double) async -> VadSessionHandle?

/// Optional additive capability for streaming transcribers that need
/// a caller-supplied VAD silence threshold to derive end-of-utterance
/// boundaries.
public protocol VadBoundaryStreamingTranscriber: StreamingTranscriber {
    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>,
        eouSilenceThresholdSeconds: Double
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error>
}
