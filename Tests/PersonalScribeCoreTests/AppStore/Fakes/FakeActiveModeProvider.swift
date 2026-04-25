import Foundation
import PersonalScribeCore

final class FakeActiveModeProvider: @unchecked Sendable, AppStoreActiveModeProviding {
    private var currentMode: WorkflowMode?
    private var continuations: [UUID: AsyncStream<WorkflowMode?>.Continuation] = [:]

    init(initialActiveMode: WorkflowMode? = nil) {
        currentMode = initialActiveMode
    }

    func currentActiveMode() -> WorkflowMode? {
        currentMode
    }

    func activeModeStream() -> AsyncStream<WorkflowMode?> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentMode)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    func emit(_ mode: WorkflowMode?) {
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
    }
}
