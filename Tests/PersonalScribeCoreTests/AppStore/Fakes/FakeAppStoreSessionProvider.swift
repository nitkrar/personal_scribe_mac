import Foundation
import PersonalScribeCore

final class FakeAppStoreSessionProvider: @unchecked Sendable, AppStoreSessionProviding {
    private static let idleProgress = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    private var currentSnapshot: SessionSnapshot
    private var snapshotContinuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]

    init(
        initialState: SessionState = .idle,
        initialProgress: ModelDownloadProgress = FakeAppStoreSessionProvider.idleProgress,
        lastResult: TranscriptionResult? = nil
    ) {
        currentSnapshot = SessionSnapshot(
            sessionState: initialState,
            lastCompletedResult: lastResult,
            modelDownloadProgress: Self.normalize(initialProgress)
        )
    }

    func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentSnapshot)
            self.snapshotContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.snapshotContinuations[id] = nil
            }
        }
    }

    func emitState(_ state: SessionState) {
        currentSnapshot.sessionState = state
        emitSnapshot(currentSnapshot)
    }

    func emitProgress(_ progress: ModelDownloadProgress) {
        currentSnapshot.modelDownloadProgress = Self.normalize(progress)
        emitSnapshot(currentSnapshot)
    }

    func setLastResult(_ result: TranscriptionResult?) {
        currentSnapshot.lastCompletedResult = result
    }

    func emitSnapshot(_ snapshot: SessionSnapshot) {
        currentSnapshot = snapshot
        for continuation in snapshotContinuations.values {
            continuation.yield(snapshot)
        }
    }

    private static func normalize(_ progress: ModelDownloadProgress) -> ModelDownloadProgress? {
        switch progress.phase {
        case .idle, .finished:
            return nil
        case .downloading, .loading:
            return progress
        }
    }
}
