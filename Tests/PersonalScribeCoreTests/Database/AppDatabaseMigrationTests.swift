import Foundation
import GRDB
import XCTest
@testable import PersonalScribeCore

/// Characterization tests for the SQLite schema delivered by the current `SQLiteTranscriptStore`
/// migrator (Phase 3.D). Pins `sqlite_master.sql` byte-for-byte so the storage-layer refactor
/// (plan `plans/storage-database-layer.md`, backlog #026) can swap in an `AppDatabase`-owned
/// migrator without drifting the wire-level DDL. A failure here is deliberate: any DDL change
/// belongs in a locked migration plan, not accidental whitespace/formatting drift.
final class AppDatabaseMigrationTests: XCTestCase {
    private let fileManager = FileManager.default

    func test_currentMigrator_pinsSQLiteMasterDDL() async throws {
        let recordings = try makeTempRecordingsDir()
        defer { cleanup(recordings) }

        _ = try SQLiteTranscriptStore(recordingsDirectory: recordings)

        let databaseURL = recordings.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let dumped = try dumpSchema(at: databaseURL)

        XCTAssertEqual(dumped, Self.expectedSchemaDump, diffMessage(actual: dumped, expected: Self.expectedSchemaDump))
    }

    // MARK: - Expected DDL (byte-identical pin)

    /// Format: `<type> <name>\n<sql>\n---\n` per entry, excluding SQLite-internal and GRDB-internal
    /// bookkeeping objects. Entries ordered by (type, name). Pinned against the DDL emitted by the
    /// current `SQLiteTranscriptStore.makeMigrator()` as of plan freeze (storage-database-layer.md).
    private static let expectedSchemaDump = """
    table transcripts
    CREATE TABLE transcripts (
        id TEXT PRIMARY KEY NOT NULL,
        timestamp REAL NOT NULL,
        text TEXT NOT NULL,
        audio_duration REAL NOT NULL,
        processing_duration REAL NOT NULL
    )
    ---
    table transcripts_fts
    CREATE VIRTUAL TABLE "transcripts_fts" USING fts5(text, tokenize='''unicode61'' ''remove_diacritics'' ''2''', content='transcripts')
    ---
    table transcripts_fts_config
    CREATE TABLE 'transcripts_fts_config'(k PRIMARY KEY, v) WITHOUT ROWID
    ---
    table transcripts_fts_data
    CREATE TABLE 'transcripts_fts_data'(id INTEGER PRIMARY KEY, block BLOB)
    ---
    table transcripts_fts_docsize
    CREATE TABLE 'transcripts_fts_docsize'(id INTEGER PRIMARY KEY, sz BLOB)
    ---
    table transcripts_fts_idx
    CREATE TABLE 'transcripts_fts_idx'(segid, term, pgno, PRIMARY KEY(segid, term)) WITHOUT ROWID
    ---
    trigger __transcripts_fts_ad
    CREATE TRIGGER "__transcripts_fts_ad" AFTER DELETE ON "transcripts" BEGIN
        INSERT INTO "transcripts_fts"("transcripts_fts", "rowid", "text") VALUES('delete', old."rowid", old."text");
    END
    ---
    trigger __transcripts_fts_ai
    CREATE TRIGGER "__transcripts_fts_ai" AFTER INSERT ON "transcripts" BEGIN
        INSERT INTO "transcripts_fts"("rowid", "text") VALUES (new."rowid", new."text");
    END
    ---
    trigger __transcripts_fts_au
    CREATE TRIGGER "__transcripts_fts_au" AFTER UPDATE ON "transcripts" BEGIN
        INSERT INTO "transcripts_fts"("transcripts_fts", "rowid", "text") VALUES('delete', old."rowid", old."text");
        INSERT INTO "transcripts_fts"("rowid", "text") VALUES (new."rowid", new."text");
    END
    """

    // MARK: - Helpers

    private func dumpSchema(at databaseURL: URL) throws -> String {
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)
        let rows = try queue.read { db in
            try Row.fetchAll(
                db,
                sql: """
                SELECT type, name, sql
                FROM sqlite_master
                WHERE name NOT LIKE 'sqlite_%'
                  AND name NOT LIKE 'grdb_%'
                  AND sql IS NOT NULL
                ORDER BY type, name
                """
            )
        }

        return rows.map { row in
            let type = row["type"] as? String ?? "?"
            let name = row["name"] as? String ?? "?"
            let sql = row["sql"] as? String ?? ""
            return "\(type) \(name)\n\(sql)"
        }.joined(separator: "\n---\n")
    }

    private func diffMessage(actual: String, expected: String) -> String {
        guard actual != expected else { return "" }
        return """
        sqlite_master DDL drifted from pinned contract.

        EXPECTED:
        \(expected)

        ACTUAL:
        \(actual)
        """
    }

    private func makeTempRecordingsDir() throws -> URL {
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("AppDatabaseMigrationTests-\(UUID().uuidString)", isDirectory: true)
        let recordings = root.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        return recordings
    }

    private func cleanup(_ recordings: URL) {
        try? fileManager.removeItem(at: recordings.deletingLastPathComponent())
    }
}
