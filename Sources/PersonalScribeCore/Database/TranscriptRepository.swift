import Foundation
import GRDB

/// The one CRUD surface for `transcripts` per plan §3 (Q-F1 locked). Raw SQL
/// and GRDB record protocols do not escape this type; every caller in the app
/// composes `TranscriptRepository(database:)` against the shared `AppDatabase`
/// and uses the async methods below.
///
/// Error posture (plan §3):
/// - **Writes throw** `TranscriptStorageError.queryFailed(underlying:)`. Session
///   pipeline re-queue + UI toast logic depends on seeing failures.
/// - **Reads are non-throwing.** Failures are logged via `PersonalScribeLogger`
///   and yield an empty result. Callers treat empty as "nothing to show", not
///   "everything failed" — publishing read failures into the banner/Settings
///   row is explicitly scope-split to backlog #043.
///
/// SQL shape parity with `SQLiteTranscriptStore` (lines 78-175) is maintained
/// so Pass 2 can delete the legacy store without query-plan drift.
public struct TranscriptRepository: Sendable, TranscriptReading, TranscriptDeleting, TranscriptUpdating {
    private static let transcriptsFTSTableName = "transcripts_fts"

    private let database: AppDatabase
    private let logger: PersonalScribeLogger
    private let operationObserver: any DatabaseOperationObserving
    private let notificationCenter: NotificationCenter

    /// Pass 1 init takes the shared database plus an optional per-operation
    /// observer. Plan §3 Q-F1: "no raw `DatabaseReader`/`DatabaseWriter`
    /// injection" — construct via the owner so "repository exists ⇒ database
    /// is open and migrated" is a compile-time contract.
    ///
    /// The `operationObserver` default is a non-optional null sink (backlog
    /// #043): every callsite either opts into a real observer or gets the
    /// no-op, never nil — so "forgot to inject" is impossible to hide.
    public init(
        database: AppDatabase,
        operationObserver: any DatabaseOperationObserving = NullDatabaseOperationObserver(),
        notificationCenter: NotificationCenter = .default,
        logger: PersonalScribeLogger
    ) {
        self.database = database
        self.logger = logger
        self.operationObserver = operationObserver
        self.notificationCenter = notificationCenter
    }

    // MARK: - Write

    /// Appends a transcript entry. Uses `TranscriptEntry.insert(db)` via the
    /// `PersistableRecord` conformance added in step 1.3 — we do NOT
    /// re-implement raw `INSERT INTO transcripts (...)` here.
    ///
    /// Any GRDB failure is re-wrapped as
    /// `TranscriptStorageError.queryFailed(underlying:)` so callers observe
    /// one envelope type regardless of which layer surfaced the failure.
    public func append(_ entry: TranscriptEntry) async throws {
        do {
            try await database.write { db in
                try entry.insert(db)
            }
            operationObserver.record(.writeSucceeded)
        } catch let error as TranscriptStorageError {
            // Already the right envelope (e.g. propagated from a future layer).
            operationObserver.record(.writeFailed)
            throw error
        } catch {
            operationObserver.record(.writeFailed)
            throw TranscriptStorageError.queryFailed(underlying: error)
        }
    }

    /// Deletes the transcript row for `id`. This only removes the SQLite row;
    /// any optional on-disk audio sidecars are intentionally left untouched
    /// until ticket #069 owns that lifecycle.
    public func delete(id: UUID) async throws {
        do {
            try await database.write { db in
                try db.execute(
                    sql: "DELETE FROM transcripts WHERE id = ?",
                    arguments: [id.uuidString]
                )
            }
            notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)
            operationObserver.record(.writeSucceeded)
        } catch let error as TranscriptStorageError {
            operationObserver.record(.writeFailed)
            throw error
        } catch {
            operationObserver.record(.writeFailed)
            throw TranscriptStorageError.queryFailed(underlying: error)
        }
    }

    /// Replaces the transcript text for `id`. Unknown row ids are surfaced as
    /// `TranscriptStorageError.updateFailed` so callers can keep stale UI state
    /// from pretending a save succeeded.
    public func update(id: UUID, text: String) async throws {
        do {
            let rowsUpdated = try await database.write { db -> Int in
                try db.execute(
                    sql: "UPDATE transcripts SET text = ? WHERE id = ?",
                    arguments: [text, id.uuidString]
                )
                return db.changesCount
            }
            guard rowsUpdated > 0 else {
                throw TranscriptStorageError.updateFailed
            }
            notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)
            operationObserver.record(.writeSucceeded)
        } catch let error as TranscriptStorageError {
            operationObserver.record(.writeFailed)
            throw error
        } catch {
            operationObserver.record(.writeFailed)
            throw TranscriptStorageError.queryFailed(underlying: error)
        }
    }

    // MARK: - Reads (non-throwing; swallow + log)

    /// Most recent `limit` entries in reverse-chronological order. A non-
    /// positive limit returns `[]` without touching SQLite — matches the guard
    /// in `SQLiteTranscriptStore.recent` (lines 101-103).
    public func recent(limit: Int) async -> [TranscriptEntry] {
        guard limit > 0 else {
            return []
        }

        do {
            let entries = try await database.read { db in
                try TranscriptEntry.fetchAll(
                    db,
                    sql: """
                    SELECT
                        id,
                        timestamp,
                        text,
                        audio_duration,
                        processing_duration
                    FROM transcripts
                    ORDER BY timestamp DESC
                    LIMIT ?
                    """,
                    arguments: [limit]
                )
            }
            operationObserver.record(.readSucceeded)
            return entries
        } catch is CancellationError {
            // Caller (e.g. SwiftUI view) tore down before the query
            // finished. Not a failure; don't pollute errors.log.
            return []
        } catch {
            logger.error("TranscriptRepository.recent failed", error: error)
            operationObserver.record(.readFailed)
            return []
        }
    }

    /// Total transcript count. Non-throwing; logs + returns 0 on failure.
    public func count() async -> Int {
        do {
            let result = try await database.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
            }
            operationObserver.record(.readSucceeded)
            return result
        } catch is CancellationError {
            return 0
        } catch {
            logger.error("TranscriptRepository.count failed", error: error)
            operationObserver.record(.readFailed)
            return 0
        }
    }

    /// FTS5 search against `transcripts_fts`. Empty/whitespace queries short-
    /// circuit to `[]`. Results are joined back to `transcripts` on rowid and
    /// ordered by `timestamp DESC`. Non-throwing by policy — FTS pattern
    /// compilation failures (e.g. malformed raw query) log and return `[]`.
    public func search(query: String) async -> [TranscriptEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        do {
            let entries = try await database.read { db in
                let pattern = try db.makeFTS5Pattern(
                    rawPattern: trimmedQuery,
                    forTable: Self.transcriptsFTSTableName
                )

                return try TranscriptEntry.fetchAll(
                    db,
                    sql: """
                    SELECT
                        transcripts.id,
                        transcripts.timestamp,
                        transcripts.text,
                        transcripts.audio_duration,
                        transcripts.processing_duration
                    FROM transcripts
                    JOIN transcripts_fts
                      ON transcripts_fts.rowid = transcripts.rowid
                    WHERE transcripts_fts MATCH ?
                    ORDER BY transcripts.timestamp DESC
                    """,
                    arguments: [pattern]
                )
            }
            operationObserver.record(.readSucceeded)
            return entries
        } catch {
            logger.error("TranscriptRepository.search failed", error: error)
            operationObserver.record(.readFailed)
            return []
        }
    }

    /// Every stored transcript, newest first. Non-throwing.
    public func all() async -> [TranscriptEntry] {
        do {
            let entries = try await database.read { db in
                try TranscriptEntry.fetchAll(
                    db,
                    sql: """
                    SELECT
                        id,
                        timestamp,
                        text,
                        audio_duration,
                        processing_duration
                    FROM transcripts
                    ORDER BY timestamp DESC
                    """
                )
            }
            operationObserver.record(.readSucceeded)
            return entries
        } catch {
            logger.error("TranscriptRepository.all failed", error: error)
            operationObserver.record(.readFailed)
            return []
        }
    }

    /// Entries whose `timestamp` falls within the closed range `window`, in
    /// the caller-specified order. Window endpoints are inclusive via
    /// `BETWEEN`. Non-throwing.
    public func entries(
        in window: ClosedRange<Date>,
        orderedBy order: TranscriptOrder
    ) async -> [TranscriptEntry] {
        let lowerBound = window.lowerBound.timeIntervalSince1970
        let upperBound = window.upperBound.timeIntervalSince1970
        let orderClause: String = {
            switch order {
            case .timestampAscending: return "ASC"
            case .timestampDescending: return "DESC"
            }
        }()

        do {
            let entries = try await database.read { db in
                try TranscriptEntry.fetchAll(
                    db,
                    sql: """
                    SELECT
                        id,
                        timestamp,
                        text,
                        audio_duration,
                        processing_duration
                    FROM transcripts
                    WHERE timestamp BETWEEN ? AND ?
                    ORDER BY timestamp \(orderClause)
                    """,
                    arguments: [lowerBound, upperBound]
                )
            }
            operationObserver.record(.readSucceeded)
            return entries
        } catch is CancellationError {
            return []
        } catch {
            logger.error("TranscriptRepository.entries(in:orderedBy:) failed", error: error)
            operationObserver.record(.readFailed)
            return []
        }
    }
}
