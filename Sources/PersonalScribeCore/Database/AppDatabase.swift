import Foundation
import GRDB

/// Canonical owner of the shared `transcripts.sqlite` `DatabaseQueue`. Per the
/// storage-layer plan (plans/storage-database-layer.md §3), exactly one
/// `AppDatabase` is constructed per app process (inside `AppComposition`);
/// every caller that needs database access consumes the shared instance.
///
/// This type is a `struct` wrapping `any DatabaseWriter`, not an actor:
/// GRDB serializes internally, so an actor wrapper would add `await` cost
/// without a new guarantee (plan §3 Q-A1).
///
/// On init, we:
///   1. Ensure the recordings directory exists.
///   2. Open a `DatabaseQueue` on `<recordings>/<filename>`.
///   3. Run runtime pre-checks (SQLite version ≥ 3.38.0, FTS5 compile option)
///      against the opened queue — before migrations run.
///   4. Migrate via `TranscriptsMigrator.makeMigrator()`.
///   5. Validate the FTS5 tokenizer DDL landed the expected `unicode61`
///      tokenizer with `remove_diacritics` set to `2`.
///   6. Set 0600 permissions on the SQLite file if it's present.
///
/// Any failure at steps 1–6 surfaces as `TranscriptStorageError`. The old
/// `SQLiteTranscriptStore.OpenError` cases are re-homed as `RuntimeGateFailure`
/// and wrapped inside `TranscriptStorageError.runtimeUnsupported(...)`.
///
/// **No `storageHealth` stream here.** That observable surface is scope-split
/// to backlog #043 per plan §3; the init-time gates remain throwing.
public struct AppDatabase: Sendable {
    private static let minimumSQLiteVersion = "3.38.0"
    private static let transcriptsFTSTableName = "transcripts_fts"

    private let writer: any DatabaseWriter
    private let databaseURL: URL

    public init(
        locator: some StorageLocator,
        filename: String = "transcripts.sqlite"
    ) throws {
        let fileManager = FileManager.default
        let recordingsDirectory = locator.url(for: .recordings)
        let databaseURL = recordingsDirectory
            .appendingPathComponent(filename, isDirectory: false)
            .standardizedFileURL

        do {
            try fileManager.createDirectory(
                at: recordingsDirectory,
                withIntermediateDirectories: true
            )
        } catch {
            throw TranscriptStorageError.openFailed(underlying: error)
        }

        let dbQueue: DatabaseQueue
        do {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } catch {
            throw TranscriptStorageError.openFailed(underlying: error)
        }

        try Self.validateRuntimePrerequisites(on: dbQueue)
        try TranscriptsMigrator.makeMigrator().migrate(dbQueue)
        try Self.validatePostMigrateFTSMetadata(on: dbQueue)
        try Self.setPermissionsIfPresent(at: databaseURL, fileManager: fileManager)

        self.writer = dbQueue
        self.databaseURL = databaseURL
    }

    /// Serialized write access. Public (not `internal`) by plan §3 Q-C1 — the
    /// call-site rule that only `Sources/PersonalScribeCore/Database/` and
    /// test targets invoke `write` / `read` is enforced by code review, not
    /// access control.
    public func write<T: Sendable>(
        _ block: @Sendable (Database) throws -> T
    ) async throws -> T {
        try await writer.write(block)
    }

    /// Serialized read access. See `write` for access-control rationale.
    public func read<T: Sendable>(
        _ block: @Sendable (Database) throws -> T
    ) async throws -> T {
        try await writer.read(block)
    }

    // MARK: - Runtime gates

    private static func validateRuntimePrerequisites(on dbQueue: DatabaseQueue) throws {
        let metadata: RuntimeMetadata
        do {
            metadata = try fetchRuntimeMetadata(from: dbQueue, includeFTSTableSQL: false)
        } catch {
            throw TranscriptStorageError.openFailed(underlying: error)
        }

        guard let currentVersion = AppDatabaseSQLiteVersion(metadata.sqliteVersion),
              let minimumVersion = AppDatabaseSQLiteVersion(minimumSQLiteVersion),
              currentVersion >= minimumVersion
        else {
            throw TranscriptStorageError.runtimeUnsupported(
                .unsupportedSQLiteVersion(
                    current: metadata.sqliteVersion,
                    minimum: minimumSQLiteVersion
                )
            )
        }

        guard metadata.fts5Enabled else {
            throw TranscriptStorageError.runtimeUnsupported(.missingFTS5CompileOption)
        }
    }

    private static func validatePostMigrateFTSMetadata(on dbQueue: DatabaseQueue) throws {
        let metadata: RuntimeMetadata
        do {
            metadata = try fetchRuntimeMetadata(from: dbQueue, includeFTSTableSQL: true)
        } catch {
            throw TranscriptStorageError.openFailed(underlying: error)
        }

        // Version + compile-option checks are re-run here so both gate failures
        // surface even when the first call happens to have passed.
        guard let currentVersion = AppDatabaseSQLiteVersion(metadata.sqliteVersion),
              let minimumVersion = AppDatabaseSQLiteVersion(minimumSQLiteVersion),
              currentVersion >= minimumVersion
        else {
            throw TranscriptStorageError.runtimeUnsupported(
                .unsupportedSQLiteVersion(
                    current: metadata.sqliteVersion,
                    minimum: minimumSQLiteVersion
                )
            )
        }

        guard metadata.fts5Enabled else {
            throw TranscriptStorageError.runtimeUnsupported(.missingFTS5CompileOption)
        }

        let normalizedTokens = metadata.ftsTableSQL.map { sql in
            Set(
                sql.lowercased().split { character in
                    !(character.isLetter || character.isNumber || character == "_")
                }
            )
        }
        guard let normalizedTokens,
              normalizedTokens.contains("unicode61"),
              normalizedTokens.contains("remove_diacritics"),
              normalizedTokens.contains("2")
        else {
            throw TranscriptStorageError.runtimeUnsupported(
                .invalidFTSTokenizerConfiguration(sql: metadata.ftsTableSQL)
            )
        }
    }

    private static func fetchRuntimeMetadata(
        from dbQueue: DatabaseQueue,
        includeFTSTableSQL: Bool
    ) throws -> RuntimeMetadata {
        try dbQueue.read { db in
            let sqliteVersion = try String.fetchOne(db, sql: "SELECT sqlite_version()") ?? "0.0.0"
            let fts5Enabled = (try Int.fetchOne(
                db,
                sql: "SELECT sqlite_compileoption_used('ENABLE_FTS5')"
            ) ?? 0) != 0
            let ftsTableSQL: String?
            if includeFTSTableSQL {
                ftsTableSQL = try String.fetchOne(
                    db,
                    sql: """
                    SELECT sql
                    FROM sqlite_master
                    WHERE type = 'table' AND name = ?
                    """,
                    arguments: [transcriptsFTSTableName]
                )
            } else {
                ftsTableSQL = nil
            }

            return RuntimeMetadata(
                sqliteVersion: sqliteVersion,
                fts5Enabled: fts5Enabled,
                ftsTableSQL: ftsTableSQL
            )
        }
    }

    private static func setPermissionsIfPresent(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }
        do {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: url.path
            )
        } catch {
            throw TranscriptStorageError.openFailed(underlying: error)
        }
    }

    // MARK: - Internal types

    private struct RuntimeMetadata: Sendable, Equatable {
        let sqliteVersion: String
        let fts5Enabled: Bool
        let ftsTableSQL: String?
    }
}

// Fileprivate version of the `SQLiteVersion` comparator that lives inside
// `SQLiteTranscriptStore.swift`. Kept local so the two owners don't share a
// symbol during Pass 1 (Stage B deletes the `SQLiteTranscriptStore` copy
// along with the legacy store).
private struct AppDatabaseSQLiteVersion: Comparable {
    let major: Int
    let minor: Int
    let patch: Int

    init?(_ rawValue: String) {
        let numericComponents = rawValue
            .split(separator: ".", omittingEmptySubsequences: false)
            .prefix(3)
            .map { component -> Int in
                let digits = component.prefix { $0.isNumber }
                return Int(digits) ?? 0
            }

        guard let major = numericComponents.first else {
            return nil
        }

        self.major = major
        self.minor = numericComponents.count > 1 ? numericComponents[1] : 0
        self.patch = numericComponents.count > 2 ? numericComponents[2] : 0
    }

    static func < (lhs: AppDatabaseSQLiteVersion, rhs: AppDatabaseSQLiteVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
    }
}
