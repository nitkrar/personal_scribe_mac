import Foundation
import GRDB

public actor SQLiteTranscriptStore {
    private static let databaseFileName = "transcripts.sqlite"
    private static let jsonlFileName = "transcripts.jsonl"
    private static let transcriptsTableName = "transcripts"
    private static let transcriptsFTSTableName = "transcripts_fts"

    enum TestingEvent: Sendable, Equatable {
        case skippedCorruptJSONLLine(String)
    }

    nonisolated(unsafe) static var testingEventSink: (@Sendable (TestingEvent) -> Void)?

    private let databaseURL: URL
    private let dbQueue: DatabaseQueue
    private let logger: SeshatLogger

    public init(recordingsDirectory: URL, ringCapacity: Int = 500) throws {
        _ = max(0, ringCapacity)

        let fileManager = FileManager.default
        let logger = SeshatLogger(category: SeshatLogCategory.app)
        let databaseURL = recordingsDirectory
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
            .standardizedFileURL
        let jsonlURL = recordingsDirectory
            .appendingPathComponent(Self.jsonlFileName, isDirectory: false)
            .standardizedFileURL
        let temporaryDatabaseURL = databaseURL.appendingPathExtension("tmp")

        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try Self.bootstrapDatabaseIfNeeded(
            databaseURL: databaseURL,
            jsonlURL: jsonlURL,
            temporaryDatabaseURL: temporaryDatabaseURL,
            fileManager: fileManager,
            logger: logger
        )

        let dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.makeMigrator().migrate(dbQueue)
        try Self.setPermissionsIfPresent(at: databaseURL, fileManager: fileManager)

        self.databaseURL = databaseURL
        self.dbQueue = dbQueue
        self.logger = logger
    }

    public func append(_ entry: TranscriptEntry) async throws {
        try await dbQueue.write { db in
            try db.execute(
                sql: """
                INSERT INTO transcripts (
                    id,
                    timestamp,
                    text,
                    audio_duration,
                    processing_duration
                ) VALUES (?, ?, ?, ?, ?)
                """,
                arguments: [
                    entry.id.uuidString,
                    entry.timestamp.timeIntervalSince1970,
                    entry.text,
                    entry.audioDuration,
                    entry.processingDuration,
                ]
            )
        }
    }

    public func recent(limit: Int) async -> [TranscriptEntry] {
        guard limit > 0 else {
            return []
        }

        do {
            let persistedEntries = try await dbQueue.read { db in
                try PersistedTranscriptEntry.fetchAll(
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

            return try persistedEntries.map { try $0.transcriptEntry }
        } catch {
            logger.error("Failed to fetch recent SQLite transcripts", error: error)
            return []
        }
    }

    public func count() async -> Int {
        do {
            return try await dbQueue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM transcripts") ?? 0
            }
        } catch {
            logger.error("Failed to count SQLite transcripts", error: error)
            return 0
        }
    }

    public func search(query: String) async throws -> [TranscriptEntry] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return []
        }

        return try await dbQueue.read { db in
            let pattern = try db.makeFTS5Pattern(
                rawPattern: trimmedQuery,
                forTable: Self.transcriptsFTSTableName
            )

            let persistedEntries = try PersistedTranscriptEntry.fetchAll(
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

            return try persistedEntries.map { try $0.transcriptEntry }
        }
    }

    private static func makeMigrator(
        jsonlImportURL: URL? = nil,
        logger: SeshatLogger? = nil
    ) -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1_transcripts_table") { db in
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
        migrator.registerMigration("v2_fts_search") { db in
            try db.create(virtualTable: Self.transcriptsFTSTableName, using: FTS5()) { table in
                table.synchronize(withTable: Self.transcriptsTableName)
                table.tokenizer = .unicode61(diacritics: .remove)
                table.column("text")
            }
            try db.execute(sql: "PRAGMA user_version = 2")
        }
        migrator.registerMigration("v3_jsonl_bootstrap") { db in
            if let jsonlImportURL, let logger {
                for entry in try Self.loadJSONLEntries(from: jsonlImportURL, logger: logger) {
                    try Self.insert(entry, into: db)
                }
            }
            try db.execute(sql: "PRAGMA user_version = 3")
        }
        return migrator
    }

    private static func bootstrapDatabaseIfNeeded(
        databaseURL: URL,
        jsonlURL: URL,
        temporaryDatabaseURL: URL,
        fileManager: FileManager,
        logger: SeshatLogger
    ) throws {
        guard !fileManager.fileExists(atPath: databaseURL.path),
              fileManager.fileExists(atPath: jsonlURL.path)
        else {
            return
        }

        try removeSQLiteArtifactsIfPresent(at: temporaryDatabaseURL, fileManager: fileManager)

        do {
            let temporaryQueue = try DatabaseQueue(path: temporaryDatabaseURL.path)
            try Self.makeMigrator(jsonlImportURL: jsonlURL, logger: logger).migrate(temporaryQueue)
            try Self.setPermissionsIfPresent(at: temporaryDatabaseURL, fileManager: fileManager)
            try fileManager.moveItem(at: temporaryDatabaseURL, to: databaseURL)
            try Self.setPermissionsIfPresent(at: databaseURL, fileManager: fileManager)
        } catch {
            try? removeSQLiteArtifactsIfPresent(at: temporaryDatabaseURL, fileManager: fileManager)
            throw error
        }
    }

    private static func loadJSONLEntries(
        from jsonlURL: URL,
        logger: SeshatLogger
    ) throws -> [TranscriptEntry] {
        let data = try Data(contentsOf: jsonlURL)
        guard !data.isEmpty else {
            return []
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var entries: [TranscriptEntry] = []
        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let lineData = Data(line)

            do {
                let entry = try decoder.decode(TranscriptEntry.self, from: lineData)
                entries.append(entry)
            } catch {
                let renderedLine = String(decoding: lineData, as: UTF8.self)
                logger.error(
                    "Skipping corrupt transcript line during SQLite migration: \(renderedLine)",
                    error: error
                )
                testingEventSink?(.skippedCorruptJSONLLine(renderedLine))
            }
        }

        return entries
    }

    private static func insert(_ entry: TranscriptEntry, into db: Database) throws {
        try db.execute(
            sql: """
            INSERT INTO transcripts (
                id,
                timestamp,
                text,
                audio_duration,
                processing_duration
            ) VALUES (?, ?, ?, ?, ?)
            """,
            arguments: [
                entry.id.uuidString,
                entry.timestamp.timeIntervalSince1970,
                entry.text,
                entry.audioDuration,
                entry.processingDuration,
            ]
        )
    }

    private static func setPermissionsIfPresent(at url: URL, fileManager: FileManager) throws {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private static func removeSQLiteArtifactsIfPresent(
        at url: URL,
        fileManager: FileManager
    ) throws {
        for artifactURL in [
            url,
            url.appendingPathExtension("shm"),
            url.appendingPathExtension("wal"),
        ] where fileManager.fileExists(atPath: artifactURL.path) {
            try fileManager.removeItem(at: artifactURL)
        }
    }
}

private struct PersistedTranscriptEntry: FetchableRecord, Decodable {
    let id: String
    let timestamp: TimeInterval
    let text: String
    let audioDuration: TimeInterval
    let processingDuration: TimeInterval

    enum CodingKeys: String, CodingKey {
        case id
        case timestamp
        case text
        case audioDuration = "audio_duration"
        case processingDuration = "processing_duration"
    }

    var transcriptEntry: TranscriptEntry {
        get throws {
            guard let uuid = UUID(uuidString: id) else {
                throw SQLiteTranscriptStoreDataError.invalidIdentifier(id)
            }

            return TranscriptEntry(
                id: uuid,
                timestamp: Date(timeIntervalSince1970: timestamp),
                text: text,
                audioDuration: audioDuration,
                processingDuration: processingDuration
            )
        }
    }
}

private enum SQLiteTranscriptStoreDataError: Error {
    case invalidIdentifier(String)
}
