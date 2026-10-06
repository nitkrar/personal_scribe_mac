import Foundation

public struct MetricsWindow: Sendable, Equatable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

}

public enum MetricsRange: String, CaseIterable, Codable, Identifiable, Sendable {
    case lastSevenDays
    case lastThirtyDays
    case allTime

    public static let userDefaultsKey = "HomeMetricsRange"
    public static let `default` = MetricsRange.allTime

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .lastSevenDays: "Last 7 days"
        case .lastThirtyDays: "Last 30 days"
        case .allTime: "All time"
        }
    }

    public func window(anchoredAt referenceDate: Date, calendar: Calendar) -> MetricsWindow {
        let start: Date
        switch self {
        case .lastSevenDays:
            start = calendar.date(byAdding: .day, value: -7, to: referenceDate)
                ?? referenceDate.addingTimeInterval(-7 * 24 * 60 * 60)
        case .lastThirtyDays:
            start = calendar.date(byAdding: .day, value: -30, to: referenceDate)
                ?? referenceDate.addingTimeInterval(-30 * 24 * 60 * 60)
        case .allTime:
            start = .distantPast
        }
        return MetricsWindow(start: start, end: referenceDate)
    }

    public static func preference(defaults: UserDefaults = .standard) -> Preference<Self> {
        Preference(key: userDefaultsKey, default: .default, defaults: defaults)
    }
}

public struct AppUsage: Sendable, Equatable {
    public let name: String
    public let count: Int

    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
}

public struct MetricsRollups: Sendable, Equatable {
    public let recordings: Int
    /// Distinct apps transcripts were pasted into (#117).
    public let appsUsed: Int
    /// Most-pasted-into apps, most first, at most five.
    public let topApps: [AppUsage]
    public let words: Int
    public let minutesSaved: Double
    public let averageWPM: Double
    public let sampleCount: Int
    public let windowStart: Date
    public let windowEnd: Date

    public init(
        recordings: Int,
        appsUsed: Int = 0,
        topApps: [AppUsage] = [],
        words: Int,
        minutesSaved: Double,
        averageWPM: Double,
        sampleCount: Int,
        windowStart: Date,
        windowEnd: Date
    ) {
        self.recordings = recordings
        self.appsUsed = appsUsed
        self.topApps = topApps
        self.words = words
        self.minutesSaved = minutesSaved
        self.averageWPM = averageWPM
        self.sampleCount = sampleCount
        self.windowStart = windowStart
        self.windowEnd = windowEnd
    }

    public static func empty(window: MetricsWindow) -> Self {
        Self(
            recordings: 0,
            words: 0,
            minutesSaved: 0,
            averageWPM: 0,
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
    case rangeChange
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
    public static let transcriptCommit = Notification.Name("PersonalScribe.metrics.transcriptCommit")
}
