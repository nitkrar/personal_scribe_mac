import Foundation
import PersonalScribeCore

public struct SessionCoordinatorAppStoreAdapter: AppStoreSessionProviding, Sendable {
    private let coordinator: SessionCoordinator

    public init(coordinator: SessionCoordinator) {
        self.coordinator = coordinator
    }

    public func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let coordinator = self.coordinator

        return AsyncStream { continuation in
            let bridgeTask = Task {
                let upstream = await coordinator.snapshotStream()

                for await snapshot in upstream {
                    guard !Task.isCancelled else {
                        break
                    }

                    continuation.yield(snapshot)
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                bridgeTask.cancel()
            }
        }
    }
}

public extension SessionCoordinator {
    nonisolated func appStoreSessionProvider() -> SessionCoordinatorAppStoreAdapter {
        SessionCoordinatorAppStoreAdapter(coordinator: self)
    }
}
