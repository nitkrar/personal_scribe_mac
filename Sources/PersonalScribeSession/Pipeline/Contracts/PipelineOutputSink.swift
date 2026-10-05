import PersonalScribeCore

public protocol PipelineOutputSink: Sendable {
    func deliverPartial(_ revision: TranscriptProgress) async throws
    /// The recipe's output stage — the last step of a session that
    /// produced a result. `sinks` are the session's bound output sinks
    /// (clipboard / paste / …). Never called for cancelled, short-exit or
    /// failed sessions. Returns the app name it was pasted into, or nil
    /// when it wasn't pasted.
    @discardableResult
    func deliverFinal(_ result: TranscriptionResult, sinks: [BoundOutputSink]) async throws -> String?
    func deliverFinalWithoutPaste(_ result: TranscriptionResult) async throws
    func resetForNewSession() async
    /// #033 — invoked on every session-end path (success, cancel, error,
    /// short-exit) so session-scoped sinks (e.g. live cursor output)
    /// can release per-session state. Default no-op so batch-only sinks
    /// don't have to opt in.
    func endSession() async
}

public extension PipelineOutputSink {
    func endSession() async {}

    func deliverFinalWithoutPaste(_ result: TranscriptionResult) async throws {
        try await deliverFinal(
            result,
            sinks: [.clipboard(restoreEnabled: false)]
        )
    }
}
