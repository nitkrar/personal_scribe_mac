import Foundation

public struct MetricsWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    public static func rollingSevenDays(
        anchoredAt referenceDate: Date,
        calendar: Calendar
    ) -> Self {
        let start = calendar.date(byAdding: .day, value: -7, to: referenceDate)
            ?? referenceDate.addingTimeInterval(-7 * 24 * 60 * 60)
        return Self(start: start, end: referenceDate)
    }
}

public struct MetricsRollups: Sendable, Equatable {
    public let recordingsThisWeek: Int
    public let wordsThisWeek: Int
    public let minutesSavedThisWeek: Double
    public let averageWPMThisWeek: Double
    public let sampleCount: Int
    public let windowStart: Date
    public let windowEnd: Date

    public init(
        recordingsThisWeek: Int,
        wordsThisWeek: Int,
        minutesSavedThisWeek: Double,
        averageWPMThisWeek: Double,
        sampleCount: Int,
        windowStart: Date,
        windowEnd: Date
    ) {
        self.recordingsThisWeek = recordingsThisWeek
        self.wordsThisWeek = wordsThisWeek
        self.minutesSavedThisWeek = minutesSavedThisWeek
        self.averageWPMThisWeek = averageWPMThisWeek
        self.sampleCount = sampleCount
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    public static func empty(window: MetricsWindow) -> Self {
        Self(
            recordingsThisWeek: 0,
            wordsThisWeek: 0,
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 0,
            sampleCount: 0,
            windowStart: window.start,
            windowEnd: window.end
        )
    }
}

public enum MetricsRefreshReason: String, Sendable, Equatable {
    case initialLoad
    case windowFocus
    case transcriptCommit
}

public struct MetricsSnapshot: Sendable, Equatable {
    public let rollups: MetricsRollups
    public let recentTranscriptions: [TranscriptEntry]
    public let lastUpdatedAt: Date
    public let lastRefreshReason: MetricsRefreshReason

    public init(
        rollups: MetricsRollups,
        recentTranscriptions: [TranscriptEntry],
        lastUpdatedAt: Date,
        lastRefreshReason: MetricsRefreshReason
    ) {
        self.rollups = rollups
        self.recentTranscriptions = recentTranscriptions
        self.lastUpdatedAt = lastUpdatedAt
        self.lastRefreshReason = lastRefreshReason
    }
}

public enum MetricsNotification {
    public static let transcriptCommit = Notification.Name("Seshat.metrics.transcriptCommit")
}
