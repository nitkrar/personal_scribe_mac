import Foundation

/// Resolved output-sink config (#078 L25 eager-binding; #089 promoted
/// to Core).
///
/// `BoundOutputSink` is the single source of truth at delivery time
/// (#089 L-24). The session's `[BoundOutputSink]` is captured at
/// session start and remains immutable for the session's lifetime;
/// `OutputService.deliverBatch(text:sinks:)` walks the array, treating
/// sink presence as the feature gate (no `.clipboard` ⇒ no clipboard
/// write, no `.frontmostPaste` ⇒ no Cmd+V).
///
/// Lives in `PersonalScribeCore` so the `OutputService` protocol
/// (Core) can reference it without inducing a dependency cycle —
/// `PersonalScribeSession` already imports Core, not the other way
/// around (codex IMPL-review-1 §1).
public enum BoundOutputSink: Sendable, Equatable, Codable {
    case clipboard(restoreEnabled: Bool)
    case frontmostPaste(enabled: Bool)
    case transcriptHistorySQLite

    private enum Discriminator: String, Codable {
        case clipboard
        case frontmostPaste
        case transcriptHistorySQLite
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case restoreEnabled
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .clipboard:
            let restore = try container.decode(Bool.self, forKey: .restoreEnabled)
            self = .clipboard(restoreEnabled: restore)
        case .frontmostPaste:
            let enabled = try container.decode(Bool.self, forKey: .enabled)
            self = .frontmostPaste(enabled: enabled)
        case .transcriptHistorySQLite:
            self = .transcriptHistorySQLite
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clipboard(let restore):
            try container.encode(Discriminator.clipboard, forKey: .type)
            try container.encode(restore, forKey: .restoreEnabled)
        case .frontmostPaste(let enabled):
            try container.encode(Discriminator.frontmostPaste, forKey: .type)
            try container.encode(enabled, forKey: .enabled)
        case .transcriptHistorySQLite:
            try container.encode(Discriminator.transcriptHistorySQLite, forKey: .type)
        }
    }
}
