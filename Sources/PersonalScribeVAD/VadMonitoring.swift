import Foundation

/// Event surfaced by a VAD session.
///
/// - `.speechEnded` fires at the tail of a speech-then-silence pattern.
///   The first-chunk gate is implicit: requires a prior speech-start
///   inside the Silero streaming state machine.
/// - `.speechResumed` fires when Silero detects speech AFTER a prior
///   `.speechEnded` has been emitted — i.e. the user starts talking
///   again during or after a grace window. Consumer uses this to
///   cancel a pending grace. Added for #046 Stage B.
public enum VadEvent: Sendable, Equatable {
    case speechEnded
    case speechResumed
}

/// Type-erased handle to a per-capture VAD session. Orchestrator holds one of
/// these as a local for the lifetime of a single `consumeCaptureStream` loop
/// and discards it when the loop exits. `nil` handle from the provider means
/// "feature unavailable for this session" — the orchestrator skips VAD wiring
/// without surfacing any error to the user.
public struct VadSessionHandle: Sendable {
    public let ingest: @Sendable ([Float]) async -> VadEvent?

    public init(ingest: @escaping @Sendable ([Float]) async -> VadEvent?) {
        self.ingest = ingest
    }
}

/// Long-lived factory for per-capture VAD sessions. Concrete implementations
/// own the CoreML model (~1 MB Silero, loaded once per process, cached).
/// `makeSession` returning `nil` is the silent-disable path — bundled model
/// missing/corrupt or any other load-time failure. Not routed through
/// `SessionState.error`.
public protocol VadProviding: Sendable {
    func makeSession(silenceThresholdSeconds: Double) async -> VadSessionHandle?
}
