import Foundation
import PersonalScribeCore

final class FakeActiveModeProvider: @unchecked Sendable, AppStoreActiveModeProviding {
    private var currentMode: LegacyWorkflowMode?
    private var continuations: [UUID: AsyncStream<LegacyWorkflowMode?>.Continuation] = [:]

    init(initialActiveMode: LegacyWorkflowMode? = nil) {
        currentMode = initialActiveMode
    }

    func currentActiveMode() -> LegacyWorkflowMode? {
        currentMode
    }

    func activeModeStream() -> AsyncStream<LegacyWorkflowMode?> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentMode)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    func emit(_ mode: LegacyWorkflowMode?) {
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
    }
}
