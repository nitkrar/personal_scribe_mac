import Foundation
import SeshatCore

public struct AppKitActiveModeProvider: AppStoreActiveModeProviding, Sendable {
    public init() {}

    public func currentActiveMode() -> ModeDescriptor? {
        ModeRegistry.descriptor(for: ModeRegistry.defaultModeID) ?? ModeRegistry.dictation
    }

    public func activeModeStream() -> AsyncStream<ModeDescriptor?> {
        AsyncStream { continuation in
            continuation.yield(currentActiveMode())
            continuation.finish()
        }
    }
}
