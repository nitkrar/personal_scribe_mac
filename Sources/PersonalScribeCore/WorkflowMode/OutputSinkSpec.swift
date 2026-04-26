import Foundation

/// Recipe-level declaration of an output sink (#078 L20). Output sinks
/// consume the final structured pipeline output and perform side
/// effects (clipboard write, paste keystroke synth, transcript SQLite
/// insert).
///
/// Cases:
/// - `.clipboard(restoreEnabled:)` — write transcript to NSPasteboard.
///   `restoreEnabled` is a `Parameter<Bool>` controlling whether the
///   prior clipboard contents are restored after a paste delay
///   (`ClipboardRestoreDelay`).
/// - `.frontmostPaste` — synthesize Cmd+V into the frontmost app via
///   CGEventPost. No parameters today (the paste-pipeline PID probe
///   in #042 is universal, not per-recipe).
/// - `.transcriptHistorySQLite` — insert into the transcript history
///   store unconditionally per the Phase 3 "notes = transcripts"
///   policy. No parameters.
public enum OutputSinkSpec: Codable, Equatable, Sendable {
    case clipboard(restoreEnabled: Parameter<Bool>)
    case frontmostPaste
    case transcriptHistorySQLite

    private enum Discriminator: String, Codable {
        case clipboard
        case frontmostPaste
        case transcriptHistorySQLite
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case restoreEnabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Discriminator.self, forKey: .type)
        switch type {
        case .clipboard:
            let restoreEnabled = try container.decode(
                Parameter<Bool>.self,
                forKey: .restoreEnabled
            )
            self = .clipboard(restoreEnabled: restoreEnabled)
        case .frontmostPaste:
            self = .frontmostPaste
        case .transcriptHistorySQLite:
            self = .transcriptHistorySQLite
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clipboard(let restoreEnabled):
            try container.encode(Discriminator.clipboard, forKey: .type)
            try container.encode(restoreEnabled, forKey: .restoreEnabled)
        case .frontmostPaste:
            try container.encode(Discriminator.frontmostPaste, forKey: .type)
        case .transcriptHistorySQLite:
            try container.encode(
                Discriminator.transcriptHistorySQLite,
                forKey: .type
            )
        }
    }
}
