import Foundation
import PersonalScribeCore

public struct SessionCoordinatorAppStoreAdapter: AppStoreSessionProviding, Sendable {
    private final class LastResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: TranscriptionResult?

        func load() -> TranscriptionResult? {
            lock.lock()
            defer { lock.unlock() }
            return value
        }

        func store(_ newValue: TranscriptionResult?) {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }

    private let coordinator: SessionCoordinator
    private let lastResultBox = LastResultBox()

    public init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    public func stateStream() -> AsyncStream<SessionState> {
        let coordinator = self.coordinator
        let lastResultBox = self.lastResultBox

        return AsyncStream { continuation in
            let bridgeTask = Task {
                let upstream = await coordinator.stateStream()

                for await state in upstream {
                    guard !Task.isCancelled else {
                        break
                    }

                    if case .idle = state {
                        lastResultBox.store(await coordinator.lastResult())
                    }

                    continuation.yield(state)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                bridgeTask.cancel()
            }
        }
    }

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        let coordinator = self.coordinator

        return AsyncStream { continuation in
            let bridgeTask = Task {
                let upstream = await coordinator.modelDownloadProgress()

                for await progress in upstream {
                    guard !Task.isCancelled else {
                        break
                    }

                    continuation.yield(progress)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                bridgeTask.cancel()
            }
        }
    }

    public func lastResult() -> TranscriptionResult? {
        lastResultBox.load()
    }
}

public extension SessionCoordinator {
    nonisolated func appStoreSessionProvider() -> SessionCoordinatorAppStoreAdapter {
        SessionCoordinatorAppStoreAdapter(coordinator: self)
    }
}
