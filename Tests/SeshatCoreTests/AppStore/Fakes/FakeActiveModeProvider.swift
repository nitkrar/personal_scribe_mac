import Foundation
import SeshatCore

final class FakeActiveModeProvider: @unchecked Sendable, AppStoreActiveModeProviding {
    private var currentMode: ModeDescriptor?
    private var continuations: [UUID: AsyncStream<ModeDescriptor?>.Continuation] = [:]

    init(initialActiveMode: ModeDescriptor? = nil) {
        currentMode = initialActiveMode
    }

    func currentActiveMode() -> ModeDescriptor? {
        currentMode
    }

    func activeModeStream() -> AsyncStream<ModeDescriptor?> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentMode)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    func emit(_ mode: ModeDescriptor?) {
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
    }
}
