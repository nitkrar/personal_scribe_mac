import Foundation

public final class SQLiteMetricsService: MetricsSnapshotLoading, @unchecked Sendable {
    public static let assumedTypingWPM = 40
    public static let defaultRecentLimit = 3

    private let reader: any MetricsReading
    private let calendar: Calendar
    private let referenceDateProvider: @Sendable () -> Date
    private let recentLimit: Int

    public convenience init(
        databaseURL: URL,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit
    ) throws {
        let reader = try SQLiteMetricsReader(
            databaseURL: databaseURL,
            referenceDateProvider: referenceDateProvider
        )
        self.init(
            reader: reader,
            calendar: calendar,
            referenceDateProvider: referenceDateProvider,
            recentLimit: recentLimit
        )
    }

    init(
        reader: any MetricsReading,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit
    ) {
        self.reader = reader
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
        try await reader.recentTranscriptions(limit: max(0, limit))
    }

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        try await reader.loadSnapshot(window: window, recentLimit: max(0, recentLimit))
    }

    private func currentSnapshot() async throws -> MetricsSnapshot {
        let window = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDateProvider(),
            calendar: calendar
        )
        return try await loadSnapshot(window: window, recentLimit: recentLimit)
    }
}
