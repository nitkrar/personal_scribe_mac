import Foundation

/// Computes rollups + surfaces recent transcriptions directly from the shared
/// `TranscriptRepository`. Pass 3 absorbed the queries + rollup math that used
/// to live in `SQLiteMetricsReader` — plan §4 Pass 3: "SQLiteMetricsReader's
/// queries + shadow-struct row decoder + executeWriteForTesting seam all
/// collapse into `TranscriptRepository` + `TranscriptEntry`." The shadow
/// `MetricsTranscriptRow` struct is gone; reads go through
/// `TranscriptRepository.entries(in:orderedBy:)` / `.recent(limit:)`, which
/// already decode to `TranscriptEntry` via its `FetchableRecord` conformance.
public final class SQLiteMetricsService: MetricsSnapshotLoading, MetricsReading, @unchecked Sendable {
    public static let assumedTypingWPM = 40
    public static let defaultRecentLimit = 3

    private let repository: TranscriptRepository
    private let calendar: Calendar
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
        self.calendar = calendar
        self.referenceDateProvider = referenceDateProvider
        self.recentLimit = max(0, recentLimit)
    }

    public func recordingsThisWeek() async throws -> Int {
        let snapshot = try await currentSnapshot()
        return snapshot.rollups.recordingsThisWeek
    }

    public func wordsThisWeek() async throws -> Int {
        let snapshot = try await currentSnapshot()
        return snapshot.rollups.wordsThisWeek
    }

    public func minsSavedThisWeek() async throws -> Duration {
        let snapshot = try await currentSnapshot()
        return .seconds(snapshot.rollups.minutesSavedThisWeek * 60)
    }

    public func wpmAverageThisWeek() async throws -> Double {
        let snapshot = try await currentSnapshot()
        return snapshot.rollups.averageWPMThisWeek
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

        let wordsThisWeek = windowEntries.reduce(into: 0) { partial, entry in
            partial += Self.wordCount(in: entry.text)
        }
        let audioMinutes = windowEntries.reduce(into: 0.0) { partial, entry in
            partial += entry.audioDuration / 60
        }
        let minutesSaved = max(
            (Double(wordsThisWeek) / Double(SQLiteMetricsService.assumedTypingWPM)) - audioMinutes,
            0
        )
        let averageWPM = audioMinutes > 0 ? Double(wordsThisWeek) / audioMinutes : 0

        return MetricsSnapshot(
            rollups: MetricsRollups(
                recordingsThisWeek: windowEntries.count,
                wordsThisWeek: wordsThisWeek,
                minutesSavedThisWeek: minutesSaved,
                averageWPMThisWeek: averageWPM,
                sampleCount: windowEntries.count,
                windowStart: window.start,
                windowEnd: window.end
            ),
            recentTranscriptions: recentEntries,
            lastUpdatedAt: referenceDateProvider(),
            lastRefreshReason: .initialLoad
        )
    }

    private func currentSnapshot() async throws -> MetricsSnapshot {
        let window = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDateProvider(),
            calendar: calendar
        )
        return try await loadSnapshot(window: window, recentLimit: recentLimit)
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
