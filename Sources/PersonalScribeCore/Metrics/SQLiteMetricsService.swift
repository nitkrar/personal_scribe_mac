import Foundation

/// Computes rollups + surfaces recent transcriptions directly from the shared
/// `TranscriptRepository`. Pass 3 absorbed the queries + rollup math that used
/// to live in `SQLiteMetricsReader` — plan §4 Pass 3: "SQLiteMetricsReader's
/// queries + shadow-struct row decoder + executeWriteForTesting seam all
/// collapse into `TranscriptRepository` + `TranscriptEntry`." The shadow
/// `MetricsTranscriptRow` struct is gone; reads go through
/// `TranscriptRepository.entries(in:orderedBy:)` / `.recent(limit:)`, which
/// already decode to `TranscriptEntry` via its `FetchableRecord` conformance.
public final class SQLiteMetricsService: MetricsService, MetricsReading, @unchecked Sendable {
    public static let assumedTypingWPM = 40
    public static let defaultRecentLimit = 3

    private let repository: TranscriptRepository
    private let referenceDateProvider: @Sendable () -> Date
    private let recentLimit: Int

    public init(
        appDatabase: AppDatabase,
        logger: PersonalScribeLogger,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit
    ) {
        self.repository = TranscriptRepository(database: appDatabase, logger: logger)
        self.referenceDateProvider = referenceDateProvider
        self.recentLimit = max(0, recentLimit)
    }

    public func recordings(in window: MetricsWindow) async throws -> Int {
        try await loadSnapshot(window: window, recentLimit: 0).rollups.recordings
    }

    public func words(in window: MetricsWindow) async throws -> Int {
        try await loadSnapshot(window: window, recentLimit: 0).rollups.words
    }

    public func minutesSaved(in window: MetricsWindow) async throws -> Duration {
        let minutes = try await loadSnapshot(window: window, recentLimit: 0).rollups.minutesSaved
        return .seconds(minutes * 60)
    }

    public func averageWPM(in window: MetricsWindow) async throws -> Double {
        try await loadSnapshot(window: window, recentLimit: 0).rollups.averageWPM
    }

    public func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        await repository.recent(limit: max(0, limit))
    }

    public func loadSnapshot(
        window: MetricsWindow,
        recentLimit: Int
    ) async throws -> MetricsSnapshot {
        let windowEntries = await repository.entries(
            in: window.start...window.end,
            orderedBy: .timestampDescending
        )
        let recentEntries = recentLimit > 0
            ? await repository.recent(limit: recentLimit)
            : []

        let words = windowEntries.reduce(into: 0) { partial, entry in
            partial += Self.wordCount(in: entry.text)
        }
        let audioMinutes = windowEntries.reduce(into: 0.0) { partial, entry in
            partial += entry.audioDuration / 60
        }
        let minutesSaved = max(
            (Double(words) / Double(SQLiteMetricsService.assumedTypingWPM)) - audioMinutes,
            0
        )
        let averageWPM = audioMinutes > 0 ? Double(words) / audioMinutes : 0

        return MetricsSnapshot(
            rollups: MetricsRollups(
                recordings: windowEntries.count,
                words: words,
                minutesSaved: minutesSaved,
                averageWPM: averageWPM,
                sampleCount: windowEntries.count,
                windowStart: window.start,
                windowEnd: window.end
            ),
            recentTranscriptions: recentEntries,
            lastUpdatedAt: referenceDateProvider(),
            lastRefreshReason: .initialLoad
        )
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
