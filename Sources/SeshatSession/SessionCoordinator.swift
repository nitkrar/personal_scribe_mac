import Foundation
import SeshatCore

public actor SessionCoordinator {
    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let logger: SeshatLogger

    private var currentState: SessionState = .idle
    private var mostRecentResult: TranscriptionResult?
    private var stateContinuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    public init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        logger: SeshatLogger
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.logger = logger
    }

    public func toggle() async {}

    public func state() -> SessionState {
        currentState
    }

    public func stateStream() -> AsyncStream<SessionState> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentState)
            self.stateContinuations[id] = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    public func lastResult() -> TranscriptionResult? {
        mostRecentResult
    }

    private func removeContinuation(id: UUID) {
        stateContinuations[id] = nil
    }

    private func publish(_ state: SessionState) {
        currentState = state
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }
}
