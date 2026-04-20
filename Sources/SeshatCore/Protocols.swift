import Foundation

/// The dynamic runtime error surfaced by the returned stream is always `SeshatError`,
/// even though the generic error type is `Error`.
public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    func stop() async

    /// Additive audio-level stream added in phase-2 step 2.9. Publishes a
    /// normalized `[0, 1]` RMS value at roughly 10 Hz, derived from the
    /// buffer cadence of the underlying engine (no wall-clock timer). The
    /// stream terminates when `stop()` is called or the capture fails.
    ///
    /// Conformers MAY return an empty stream if they do not expose levels
    /// (the default implementation does exactly that). UI code must not
    /// rely on the stream being non-empty — treat the absence of levels as
    /// "no meter available" and fall back to a static visual.
    func audioLevelStream() async -> AsyncStream<Float>
}

extension AudioCapturing {
    /// Default no-op implementation so existing conformers (test doubles,
    /// future fakes) do not have to expose a meter.
    public func audioLevelStream() async -> AsyncStream<Float> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }
}

public protocol Transcribing: Sendable {
    func prepare() async throws
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}

public struct ModelDownloadProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case downloading
        case loading
        case finished
    }

    public let phase: Phase
    public let fractionCompleted: Double
    public let receivedBytes: Int64
    public let expectedBytes: Int64?

    public init(
        phase: Phase,
        fractionCompleted: Double,
        receivedBytes: Int64,
        expectedBytes: Int64?
    ) {
        self.phase = phase
        self.fractionCompleted = fractionCompleted
        self.receivedBytes = receivedBytes
        self.expectedBytes = expectedBytes
    }
}
