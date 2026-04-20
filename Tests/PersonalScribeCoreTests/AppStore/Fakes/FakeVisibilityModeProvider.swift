import Foundation
import PersonalScribeCore

final class FakeVisibilityModeProvider: @unchecked Sendable, AppStoreVisibilityModeProviding {
    private var currentMode: AppStoreVisibilityMode
    private var continuations: [UUID: AsyncStream<AppStoreVisibilityMode>.Continuation] = [:]

    init(initialVisibilityMode: AppStoreVisibilityMode = .autoShow) {
        currentMode = initialVisibilityMode
    }

    func currentVisibilityMode() -> AppStoreVisibilityMode {
        currentMode
    }

    func visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentMode)
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                self?.continuations[id] = nil
            }
        }
    }

    func emit(_ mode: AppStoreVisibilityMode) {
        currentMode = mode
        for continuation in continuations.values {
            continuation.yield(mode)
        }
    }
}
