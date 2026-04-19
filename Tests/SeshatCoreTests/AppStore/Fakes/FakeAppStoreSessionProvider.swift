import Foundation
import SeshatCore

final class FakeAppStoreSessionProvider: @unchecked Sendable, AppStoreSessionProviding {
    private var currentState: SessionState
    private var currentProgress: ModelDownloadProgress
    private var currentLastResult: TranscriptionResult?
    private var stateContinuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    private var progressContinuations: [UUID: AsyncStream<ModelDownloadProgress>.Continuation] = [:]

    init(
        initialState: SessionState = .idle,
        initialProgress: ModelDownloadProgress = ModelDownloadProgress(
            phase: .idle,
            fractionCompleted: 0,
            receivedBytes: 0,
            expectedBytes: nil
        ),
        lastResult: TranscriptionResult? = nil
    ) {
        currentState = initialState
        currentProgress = initialProgress
        currentLastResult = lastResult
    }

    func stateStream() -> AsyncStream<SessionState> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentState)
            self.stateContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.stateContinuations[id] = nil
            }
        }
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentProgress)
            self.progressContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.progressContinuations[id] = nil
            }
        }
    }

    func lastResult() -> TranscriptionResult? {
        currentLastResult
    }

    func emitState(_ state: SessionState) {
        currentState = state
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }

    func emitProgress(_ progress: ModelDownloadProgress) {
        currentProgress = progress
        for continuation in progressContinuations.values {
            continuation.yield(progress)
        }
    }

    func setLastResult(_ result: TranscriptionResult?) {
        currentLastResult = result
    }
}
