import Foundation

/// On-disk schema for `workflow-modes.json` (per #078 synthesis #5).
///
/// Single document per user. Lives in `AppConfig.baseDirectory()/workflow-modes.json`.
/// Owned by `WorkflowModeRegistry` (#078.24) — read on registry init,
/// written on every default-mode / custom-mode mutation.
///
/// Fields:
/// - `schemaVersion: Int` — currently `1`. Bump when the schema
///   changes incompatibly. Decode-time validation lives in the
///   registry, not here.
/// - `defaultModeID: String?` — id of the user's chosen default mode
///   (#089). `nil` means "no default chosen" — registry resolves the
///   built-in `WorkflowMode.dictation` fallback. The runtime "current
///   mode" is in-memory only and not persisted here (L-5 + L-6).
/// - `customModes: [WorkflowMode]` — user-defined recipes.
///   Built-in recipes are not persisted here; they live in code.
///
/// Defaults: `init()` produces a fresh document with
/// `schemaVersion: 1`, `defaultModeID: nil`, empty `customModes`.
public struct WorkflowModeDocument: Codable, Equatable, Sendable {
    /// Current document schema version. Increment when the on-disk
    /// shape changes incompatibly with prior decoders.
    public static let currentSchemaVersion: Int = 1

    public var schemaVersion: Int
    public var defaultModeID: String?
    public var customModes: [WorkflowMode]

    public init(
        schemaVersion: Int = WorkflowModeDocument.currentSchemaVersion,
        defaultModeID: String? = nil,
        customModes: [WorkflowMode] = []
    ) {
        self.schemaVersion = schemaVersion
        self.defaultModeID = defaultModeID
        self.customModes = customModes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case defaultModeID
        case customModes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.defaultModeID = try container.decodeIfPresent(
            String.self,
            forKey: .defaultModeID
        )
        // Treat an absent customModes field as an empty list — keeps
        // older / hand-edited documents decode-friendly without
        // forcing the registry to special-case the missing key.
        self.customModes = try container.decodeIfPresent(
            [WorkflowMode].self,
            forKey: .customModes
        ) ?? []
    }
}
