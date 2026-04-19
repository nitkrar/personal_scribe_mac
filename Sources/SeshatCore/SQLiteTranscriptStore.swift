import Foundation
import GRDB

public actor SQLiteTranscriptStore {
    private static let databaseFileName = "transcripts.sqlite"
    private static let jsonlFileName = "transcripts.jsonl"
    private static let transcriptsTableName = "transcripts"
    private static let transcriptsFTSTableName = "transcripts_fts"
    private static let minimumSQLiteVersion = "3.38.0"

    struct RuntimeMetadata: Sendable, Equatable {
        let sqliteVersion: String
        let fts5Enabled: Bool
        let ftsTableSQL: String?
    }

    enum OpenError: Error, Equatable {
        case unsupportedSQLiteVersion(current: String, minimum: String)
        case missingFTS5CompileOption
        case invalidFTSTokenizerConfiguration(sql: String?)
    }

    enum TestingEvent: Sendable, Equatable {
        case skippedCorruptJSONLLine(String)
    }

    nonisolated(unsafe) static var testingEventSink: (@Sendable (TestingEvent) -> Void)?

    private let databaseURL: URL
    private let dbQueue: DatabaseQueue
    private let logger: SeshatLogger

    public init(recordingsDirectory: URL, ringCapacity: Int = 500) throws {
        let storageLocator = FixedBaseDirectoryStorageLocator(
            baseDirectory: recordingsDirectory.deletingLastPathComponent(),
            managedDirectoryOverrides: [.recordings: recordingsDirectory]
        )
        try self.init(storageLocator: storageLocator, ringCapacity: ringCapacity)
    }

    init(
        storageLocator: any StorageLocator,
        ringCapacity: Int = 500,
        atomicFileWriter: any AtomicFileWriter = FileManagerAtomicFileWriter()
    ) throws {
        _ = max(0, ringCapacity)

        let fileManager = FileManager.default
        let logger = SeshatLogger(category: SeshatLogCategory.app)
        let recordingsDirectory = storageLocator.url(for: .recordings)
        let databaseURL = recordingsDirectory
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
            .standardizedFileURL
        let jsonlURL = recordingsDirectory
            .appendingPathComponent(Self.jsonlFileName, isDirectory: false)
            .standardizedFileURL

        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        try Self.bootstrapDatabaseIfNeeded(
            databaseURL: databaseURL,
            jsonlURL: jsonlURL,
            fileManager: fileManager,
            atomicFileWriter: atomicFileWriter,
            logger: logger
        )

        let dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.validateRuntimePrerequisites(on: dbQueue)
        try Self.makeMigrator().migrate(dbQueue)
        try Self.validateRuntimeMetadata(Self.fetchRuntimeMetadata(from: dbQueue, includeFTSTableSQL: true))
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
        migrator.registerMigration("v4_runtime_guard_marker") { db in
            try db.execute(sql: "PRAGMA user_version = 4")
        }
        return migrator
    }

    private static func bootstrapDatabaseIfNeeded(
        databaseURL: URL,
        jsonlURL: URL,
        fileManager: FileManager,
        atomicFileWriter: any AtomicFileWriter,
        logger: SeshatLogger
    ) throws {
        guard !fileManager.fileExists(atPath: databaseURL.path),
              fileManager.fileExists(atPath: jsonlURL.path)
        else {
            return
        }

        var temporaryDatabaseURL: URL?

        do {
            try atomicFileWriter.replaceItem(at: databaseURL, permissions: 0o600) { candidateURL in
                temporaryDatabaseURL = candidateURL

                let temporaryQueue = try DatabaseQueue(path: candidateURL.path)
                try Self.validateRuntimePrerequisites(on: temporaryQueue)
                try Self.makeMigrator(jsonlImportURL: jsonlURL, logger: logger).migrate(temporaryQueue)
                try Self.setPermissionsIfPresent(at: candidateURL, fileManager: fileManager)
            }

            if let temporaryDatabaseURL {
                try? removeSQLiteArtifactsIfPresent(at: temporaryDatabaseURL, fileManager: fileManager)
            }
            try Self.setPermissionsIfPresent(at: databaseURL, fileManager: fileManager)
        } catch {
            if let temporaryDatabaseURL {
                try? removeSQLiteArtifactsIfPresent(at: temporaryDatabaseURL, fileManager: fileManager)
            }
            throw error
        }
    }

    private static func loadJSONLEntries(
        from jsonlURL: URL,
        logger: SeshatLogger
    ) throws -> [TranscriptEntry] {
        try TranscriptStoreJSONL.loadAllPersistedEntries(
            from: jsonlURL,
            logger: logger,
            onCorruptLine: { renderedLine in
                testingEventSink?(.skippedCorruptJSONLLine(renderedLine))
            }
        )
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

    static func validateRuntimeMetadata(_ metadata: RuntimeMetadata) throws {
        guard let currentVersion = SQLiteVersion(metadata.sqliteVersion),
              let minimumVersion = SQLiteVersion(minimumSQLiteVersion),
              currentVersion >= minimumVersion
        else {
            throw OpenError.unsupportedSQLiteVersion(
                current: metadata.sqliteVersion,
                minimum: minimumSQLiteVersion
            )
        }

        guard metadata.fts5Enabled else {
            throw OpenError.missingFTS5CompileOption
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
            throw OpenError.invalidFTSTokenizerConfiguration(sql: metadata.ftsTableSQL)
        }
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

    private static func validateRuntimePrerequisites(on dbQueue: DatabaseQueue) throws {
        let metadata = try fetchRuntimeMetadata(from: dbQueue, includeFTSTableSQL: false)

        guard let currentVersion = SQLiteVersion(metadata.sqliteVersion),
              let minimumVersion = SQLiteVersion(minimumSQLiteVersion),
              currentVersion >= minimumVersion
        else {
            throw OpenError.unsupportedSQLiteVersion(
                current: metadata.sqliteVersion,
                minimum: minimumSQLiteVersion
            )
        }

        guard metadata.fts5Enabled else {
            throw OpenError.missingFTS5CompileOption
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
                    arguments: [Self.transcriptsFTSTableName]
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
}

private struct SQLiteVersion: Comparable {
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

    static func < (lhs: SQLiteVersion, rhs: SQLiteVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        return lhs.patch < rhs.patch
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
