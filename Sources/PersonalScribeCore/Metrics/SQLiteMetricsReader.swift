import Foundation
import GRDB

public actor SQLiteMetricsReader: MetricsReading {
    private let source: Source
    private let referenceDateProvider: @Sendable () -> Date

    public init(
        databaseURL: URL,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init
    ) throws {
        var configuration = Configuration()
        configuration.readonly = true
        let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        self.source = .queue(queue)
        self.referenceDateProvider = referenceDateProvider
    }

    /// Pass-2 production entry (plan §4): consume the shared `AppDatabase`
    /// instead of opening a parallel read-only `DatabaseQueue`. Pass-3 deletes
    /// the legacy `init(databaseURL:)` + queue path entirely.
    public init(
        appDatabase: AppDatabase,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.source = .appDatabase(appDatabase)
        self.referenceDateProvider = referenceDateProvider
    }

    public func loadSnapshot(
        window: MetricsWindow,
        recentLimit: Int
    ) async throws -> MetricsSnapshot {
        let payload = try await read { db -> ([MetricsTranscriptRow], [MetricsTranscriptRow]) in
            let windowRows = try MetricsTranscriptRow.fetchAll(
                db,
                sql: """
                SELECT
                    id,
                    timestamp,
                    text,
                    audio_duration,
                    processing_duration
                FROM transcripts
                WHERE timestamp >= ? AND timestamp <= ?
                ORDER BY timestamp DESC
                """,
                arguments: [
                    window.start.timeIntervalSince1970,
                    window.end.timeIntervalSince1970,
                ]
            )

            let recentRows: [MetricsTranscriptRow]
            if recentLimit > 0 {
                recentRows = try MetricsTranscriptRow.fetchAll(
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
                    arguments: [recentLimit]
                )
            } else {
                recentRows = []
            }

            return (windowRows, recentRows)
        }

        let entries = try payload.0.map { try $0.transcriptEntry }
        let recentTranscriptions = try payload.1.map { try $0.transcriptEntry }
        let wordsThisWeek = entries.reduce(into: 0) { partialResult, entry in
            partialResult += Self.wordCount(in: entry.text)
        }
        let audioMinutes = entries.reduce(into: 0.0) { partialResult, entry in
            partialResult += entry.audioDuration / 60
        }
        let minutesSaved = max(
            (Double(wordsThisWeek) / Double(SQLiteMetricsService.assumedTypingWPM)) - audioMinutes,
            0
        )
        let averageWPM = audioMinutes > 0 ? Double(wordsThisWeek) / audioMinutes : 0

        return MetricsSnapshot(
            rollups: MetricsRollups(
                recordingsThisWeek: entries.count,
                wordsThisWeek: wordsThisWeek,
                minutesSavedThisWeek: minutesSaved,
                averageWPMThisWeek: averageWPM,
                sampleCount: entries.count,
                windowStart: window.start,
                windowEnd: window.end
            ),
            recentTranscriptions: recentTranscriptions,
            lastUpdatedAt: referenceDateProvider(),
            lastRefreshReason: .initialLoad
        )
    }

    public func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        guard limit > 0 else {
            return []
        }

        let rows = try await read { db in
            try MetricsTranscriptRow.fetchAll(
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

        return try rows.map { try $0.transcriptEntry }
    }

    // Internal characterization seam for tests that assert the queue is truly read-only.
    // Only meaningful for the `init(databaseURL:)` path; the `AppDatabase` path is
    // read/write-shared and this helper is not used there.
    func executeWriteForTesting(sql: String) async throws {
        switch source {
        case .queue(let dbQueue):
            try await dbQueue.writeWithoutTransaction { db in
                try db.execute(sql: sql)
            }
        case .appDatabase:
            throw SQLiteMetricsReaderDataError.writeTestHelperUnavailableForAppDatabasePath
        }
    }

    // MARK: - Read dispatch

    private func read<T: Sendable>(
        _ block: @Sendable (Database) throws -> T
    ) async throws -> T {
        switch source {
        case .queue(let dbQueue):
            return try await dbQueue.read(block)
        case .appDatabase(let appDatabase):
            return try await appDatabase.read(block)
        }
    }

    private enum Source: Sendable {
        case queue(DatabaseQueue)
        case appDatabase(AppDatabase)
    }

    private static func wordCount(in text: String) -> Int {
        var count = 0
        text.enumerateSubstrings(
            in: text.startIndex..<text.endIndex,
            options: [.byWords, .substringNotRequired]
        ) { _, _, _, _ in
            count += 1
        }
        return count
    }
}

private struct MetricsTranscriptRow: FetchableRecord, Decodable {
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
                throw SQLiteMetricsReaderDataError.invalidIdentifier(id)
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

private enum SQLiteMetricsReaderDataError: Error {
    case invalidIdentifier(String)
    case writeTestHelperUnavailableForAppDatabasePath
}
