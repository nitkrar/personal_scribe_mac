import Foundation
import GRDB

public actor SQLiteTranscriptStore {
    private static let databaseFileName = "transcripts.sqlite"

    private let databaseURL: URL
    private let dbQueue: DatabaseQueue
    private let logger: SeshatLogger

    public init(recordingsDirectory: URL, ringCapacity: Int = 500) throws {
        _ = max(0, ringCapacity)

        let fileManager = FileManager.default
        let databaseURL = recordingsDirectory
            .appendingPathComponent(Self.databaseFileName, isDirectory: false)
            .standardizedFileURL

        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let dbQueue = try DatabaseQueue(path: databaseURL.path)
        try Self.makeMigrator().migrate(dbQueue)
        try Self.setPermissionsIfPresent(at: databaseURL, fileManager: fileManager)

        self.databaseURL = databaseURL
        self.dbQueue = dbQueue
        self.logger = SeshatLogger(category: SeshatLogCategory.app)
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

    private static func makeMigrator() -> DatabaseMigrator {
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
        return migrator
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
