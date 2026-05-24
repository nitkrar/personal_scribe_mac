import Foundation
import PersonalScribeCore

public actor FakeTranscriber: Transcriber {
    public nonisolated let capabilities: TranscriberCapabilities

    private let result: TranscriptionResult
    private let prepareError: PersonalScribeError?
    private let transcribeError: PersonalScribeError?
    private let delay: Duration?

    public init(
        result: TranscriptionResult,
        prepareError: PersonalScribeError? = nil,
        transcribeError: PersonalScribeError? = nil,
        delay: Duration? = nil,
        capabilities: TranscriberCapabilities = TranscriberCapabilities()
    ) {
        self.result = result
        self.prepareError = prepareError
        self.transcribeError = transcribeError
        self.delay = delay
        self.capabilities = capabilities
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

    public func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        _ = languageHint
        try await maybeDelay()

        if let transcribeError {
            throw transcribeError
        }

        return result
    }

    public func releaseIdleResources() async {}

    private func maybeDelay() async throws {
        if let delay {
            try await Task.sleep(for: delay)
        }
    }
}
