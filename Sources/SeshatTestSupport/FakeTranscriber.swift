import Foundation
import SeshatCore

public actor FakeTranscriber: Transcribing {
    private let result: TranscriptionResult
    private let prepareError: SeshatError?
    private let transcribeError: SeshatError?
    private let delay: Duration?

    public init(
        result: TranscriptionResult,
        prepareError: SeshatError? = nil,
        transcribeError: SeshatError? = nil,
        delay: Duration? = nil
    ) {
        self.result = result
        self.prepareError = prepareError
        self.transcribeError = transcribeError
        self.delay = delay
    }

    public func prepare() async throws {
        try await maybeDelay()

        if let prepareError {
            throw prepareError
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(.init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil))
            continuation.finish()
        }
    }

    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try await maybeDelay()

        if let transcribeError {
            throw transcribeError
        }

        return result
    }

    public func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        do {
            for try await _ in stream {}
        } catch let error as SeshatError {
            throw error
        } catch {
            throw SeshatError.transcriptionFailure
        }

        return try await transcribe(
            PCMBuffer(samples: [], timestamp: ContinuousClock().now)
        )
    }

    private func maybeDelay() async throws {
        if let delay {
            try await Task.sleep(for: delay)
        }
    }
}
