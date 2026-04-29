/// Delivers a finished transcript to the user-configured output sinks
/// declared on the in-flight session's `BoundRecipe` (#089 L-24).
///
/// `sinks` is the session-frozen sink list captured by the orchestrator
/// at session start — never the live registry value at delivery
/// time. Sink presence is part of the truth: no `.clipboard` entry
/// means no clipboard write; no `.frontmostPaste` entry means no
/// Cmd+V. The associated values (e.g. `restoreEnabled`, `enabled`)
/// are already resolved booleans (per L-25 eager binding).
@MainActor
public protocol OutputService: AnyObject, Sendable {
    func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult
}
