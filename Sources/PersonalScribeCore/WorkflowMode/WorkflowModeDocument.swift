import Foundation

/// On-disk schema for `workflow-modes.json` (per #078 synthesis #5).
///
/// Single document per user. Lives in `AppConfig.baseDirectory()/workflow-modes.json`.
/// Owned by `WorkflowModeRegistry` (#078.24) — read on registry init,
/// written on every active-mode / custom-mode mutation.
///
/// Fields:
/// - `schemaVersion: Int` — currently `1`. Bump when the schema
///   changes incompatibly. Decode-time validation lives in the
///   registry, not here.
/// - `activeModeID: String?` — id of the currently-active recipe.
///   `nil` means "no preference yet" — registry resolves to the
///   built-in `dictation` default.
/// - `customModes: [WorkflowMode]` — user-defined recipes.
///   Built-in recipes are not persisted here; they live in code.
///
/// Defaults: `init()` produces a fresh document with
/// `schemaVersion: 1`, `activeModeID: nil`, empty `customModes`.
public struct WorkflowModeDocument: Codable, Equatable, Sendable {
    /// Current document schema version. Increment when the on-disk
    /// shape changes incompatibly with prior decoders.
    public static let currentSchemaVersion: Int = 1

    public var schemaVersion: Int
    public var activeModeID: String?
    public var customModes: [WorkflowMode]

    public init(
        schemaVersion: Int = WorkflowModeDocument.currentSchemaVersion,
        activeModeID: String? = nil,
        customModes: [WorkflowMode] = []
    ) {
        self.schemaVersion = schemaVersion
        self.activeModeID = activeModeID
        self.customModes = customModes
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case activeModeID
        case customModes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        self.activeModeID = try container.decodeIfPresent(
            String.self,
            forKey: .activeModeID
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
