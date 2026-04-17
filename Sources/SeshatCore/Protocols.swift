import Foundation

/// The dynamic runtime error surfaced by the returned stream is always `SeshatError`,
/// even though the generic error type is `Error`.
public protocol AudioCapturing: Sendable {
    func start() async throws -> AsyncThrowingStream<PCMBuffer, Error>
    func stop() async
}

public protocol Transcribing: Sendable {
    func prepare() async throws
    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult
}

public protocol MicrophonePermissionRequesting: Sendable {
    func requestAccess() async -> Bool
}

public struct ModelDownloadProgress: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case downloading
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
