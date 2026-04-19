import Foundation
import GRDB

public actor SQLiteMetricsReader: MetricsReading {
    private let dbQueue: DatabaseQueue
    private let referenceDateProvider: @Sendable () -> Date

    public init(
        databaseURL: URL,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init
    ) throws {
        self.dbQueue = try DatabaseQueue(path: databaseURL.path)
        self.referenceDateProvider = referenceDateProvider
    }

    public func loadSnapshot(
        window: MetricsWindow,
        recentLimit: Int
    ) async throws -> MetricsSnapshot {
        let payload = try await dbQueue.read { db in
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

        let rows = try await dbQueue.read { db in
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
}
