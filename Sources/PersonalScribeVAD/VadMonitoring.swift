import Foundation
import PersonalScribeCore

public typealias VadEvent = PersonalScribeCore.VadEvent
public typealias VadSessionHandle = PersonalScribeCore.VadSessionHandle

/// Long-lived factory for per-capture VAD sessions. Concrete implementations
/// own the CoreML model (~1 MB Silero, loaded once per process, cached).
/// `makeSession` returning `nil` is the silent-disable path — bundled model
/// missing/corrupt or any other load-time failure. Not routed through
/// `SessionState.error`.
public protocol VadProviding: Sendable {
    func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle?
    func releaseIdleResources() async
}

public extension VadProviding {
    func releaseIdleResources() async {}
}
