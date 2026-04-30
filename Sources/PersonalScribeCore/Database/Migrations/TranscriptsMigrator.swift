import Foundation
import GRDB

/// Canonical migrator for the shared `transcripts.sqlite` file owned by
/// `AppDatabase`. Ports `v1_transcripts_table`, `v2_fts_search`, and
/// `v4_runtime_guard_marker` **verbatim** from
/// `SQLiteTranscriptStore.makeMigrator()` (same DDL, same GRDB DSL, same
/// `PRAGMA user_version = N` writes). `v3_jsonl_bootstrap` is registered so
/// `grdb_migrations` rows on existing DBs stay consistent, but its body is a
/// pure `PRAGMA user_version = 3` marker — no JSONL import, because the JSONL
/// sidecar is being deleted in Pass 2 of the storage-layer plan.
///
/// Each migration body is wrapped in a do/catch that rethrows any underlying
/// error as `TranscriptStorageError.migrationFailed(version:, underlying:)`,
/// so callers of `AppDatabase.init` see which migration tripped.
enum TranscriptsMigrator {
    private static let transcriptsTableName = "transcripts"
    private static let transcriptsFTSTableName = "transcripts_fts"

    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_transcripts_table") { db in
            try wrapMigration(version: "v1_transcripts_table") {
                try db.execute(sql: """
                    CREATE TABLE transcripts (
                        id TEXT PRIMARY KEY NOT NULL,
                        timestamp REAL NOT NULL,
                        text TEXT NOT NULL,
                        audio_duration REAL NOT NULL,
                        processing_duration REAL NOT NULL
                    )
                    """)
                try db.execute(sql: "PRAGMA user_version = 1")
            }
        }

        migrator.registerMigration("v2_fts_search") { db in
            try wrapMigration(version: "v2_fts_search") {
                try db.create(virtualTable: transcriptsFTSTableName, using: FTS5()) { table in
                    table.synchronize(withTable: transcriptsTableName)
                    table.tokenizer = .unicode61(diacritics: .remove)
                    table.column("text")
                }
                try db.execute(sql: "PRAGMA user_version = 2")
            }
        }

        migrator.registerMigration("v3_jsonl_bootstrap") { db in
            try wrapMigration(version: "v3_jsonl_bootstrap") {
                // JSONL sidecar is being deleted in Pass 2 — this migration stays
                // registered only so `grdb_migrations` rows on existing DBs stay
                // consistent. No JSONL import in the new code path.
                try db.execute(sql: "PRAGMA user_version = 3")
            }
        }

        migrator.registerMigration("v4_runtime_guard_marker") { db in
            try wrapMigration(version: "v4_runtime_guard_marker") {
                try db.execute(sql: "PRAGMA user_version = 4")
            }
        }

        migrator.registerMigration("v5_mode_id") { db in
            try wrapMigration(version: "v5_mode_id") {
                // #027 — record which `WorkflowMode` produced each
                // transcript. Nullable for pre-#027 rows; new inserts
                // capture `BoundRecipe.recipeID` from
                // `SessionPipelineOrchestrator.persist`.
                try db.execute(sql: "ALTER TABLE transcripts ADD COLUMN mode_id TEXT")
                try db.execute(sql: "PRAGMA user_version = 5")
            }
        }

        return migrator
    }

    private static func wrapMigration(
        version: String,
        body: () throws -> Void
    ) throws {
        do {
            try body()
        } catch let error as TranscriptStorageError {
            // Already wrapped — don't double-wrap if a nested helper tagged it.
            throw error
        } catch {
            throw TranscriptStorageError.migrationFailed(version: version, underlying: error)
        }
    }
}
