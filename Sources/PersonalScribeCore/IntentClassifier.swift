import Foundation

/// Classification result produced by an `IntentClassifier`. These four cases
/// are the contract that Phase 4 intent routing will switch on; they are
/// stable across the Phase 2 stub and future NLEmbedding / llama.cpp
/// implementations so call sites never need to change.
///
/// - `dictation`: plain free-form speech that should be inserted as-is.
/// - `command`: an actionable request (e.g. "open settings").
/// - `query`: a question that should produce an answer (Command Mode).
/// - `unknown`: classifier could not decide; callers should fall back to
///   `dictation` for safety.
public enum Intent: Sendable, Equatable, Hashable {
    case dictation
    case command
    case query
    case unknown
}

/// Classifies transcript text into a high-level `Intent` category. Phase 4
/// will ship real implementations (rule pass → NLEmbedding similarity →
/// llama.cpp tier). Phase 2 wires the call site through `NoOpIntentClassifier`
/// so the surrounding plumbing is stable before the model plug-ins land.
///
/// Conformers MUST be `Sendable` so they can be safely held by actors
/// (`SessionCoordinator`) and called across task boundaries. The async
/// signature is intentional — NLEmbedding warm-up and llama.cpp inference
/// are both asynchronous.
public protocol IntentClassifier: Sendable {
    /// Classify the given text. Implementations should be safe to call
    /// concurrently. Must not throw: the Phase 2 contract is "always return
    /// an `Intent`" so UI flows never have to handle a classification error
    /// path (which doesn't exist yet).
    func classify(_ text: String) async -> Intent
}

/// Phase 2 placeholder implementation: every input is classified as
/// `.dictation`. This preserves the Phase 1 behaviour (all transcripts are
/// dictated text) while giving the rest of the system a stable contract to
/// depend on. Replace with the real classifier chain in Phase 4.
///
/// Deliberately zero real logic — the only reason this type exists is to
/// provide a concrete default conformer that can be injected now and swapped
/// later without call-site changes.
public struct NoOpIntentClassifier: IntentClassifier {
    public init() {}

    public func classify(_ text: String) async -> Intent {
        _ = text
        return .dictation
    }
}
