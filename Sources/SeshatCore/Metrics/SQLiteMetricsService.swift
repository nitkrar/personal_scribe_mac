import Combine
import Foundation

@MainActor
public final class SQLiteMetricsService: MetricsService, @unchecked Sendable {
    nonisolated public static let assumedTypingWPM = 40
    nonisolated public static let defaultRecentLimit = 3

    @Published public private(set) var rollups: MetricsRollups
    @Published public private(set) var recentTranscriptions: [TranscriptEntry]
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var lastRefreshReason: MetricsRefreshReason?
    @Published public private(set) var isRefreshing = false

    private let reader: any MetricsReading
    private let notificationCenter: NotificationCenter
    private let calendar: Calendar
    private let referenceDateProvider: @Sendable () -> Date
    private let recentLimit: Int
    private let logger: SeshatLogger
    private var transcriptCommitObservation: NSObjectProtocol?
    private var pendingRefreshReason: MetricsRefreshReason?
    private var isObserving = false

    public init(
        databaseURL: URL,
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = Self.defaultRecentLimit,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.app)
    ) throws {
        let reader = try SQLiteMetricsReader(
            databaseURL: databaseURL,
            referenceDateProvider: referenceDateProvider
        )
        self.init(
            reader: reader,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: referenceDateProvider,
            recentLimit: recentLimit,
            logger: logger
        )
    }

    init(
        reader: any MetricsReading,
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = Self.defaultRecentLimit,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.app)
    ) {
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.referenceDateProvider = referenceDateProvider
        self.recentLimit = max(0, recentLimit)
        self.logger = logger

        let initialWindow = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDateProvider(),
            calendar: calendar
        )
        self.rollups = MetricsRollups.empty(window: initialWindow)
        self.recentTranscriptions = []
        self.lastUpdatedAt = nil
        self.lastRefreshReason = nil
    }

    public func refresh(reason: MetricsRefreshReason) async {
        if isRefreshing {
            pendingRefreshReason = reason
            return
        }

        isRefreshing = true
        var activeReason: MetricsRefreshReason? = reason

        while let nextReason = activeReason {
            pendingRefreshReason = nil
            let refreshedAt = referenceDateProvider()
            let window = MetricsWindow.rollingSevenDays(
                anchoredAt: refreshedAt,
                calendar: calendar
            )

            do {
                let snapshot = try await reader.loadSnapshot(window: window, recentLimit: recentLimit)
                apply(
                    snapshot: MetricsSnapshot(
                        rollups: snapshot.rollups,
                        recentTranscriptions: snapshot.recentTranscriptions,
                        lastUpdatedAt: refreshedAt,
                        lastRefreshReason: nextReason
                    )
                )
            } catch {
                logger.error("Failed to refresh metrics snapshot", error: error)
            }

            activeReason = pendingRefreshReason
        }

        isRefreshing = false
    }

    public func startObserving() {
        guard !isObserving else {
            return
        }

        isObserving = true
        transcriptCommitObservation = notificationCenter.addObserver(
            forName: MetricsNotification.transcriptCommit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh(reason: .transcriptCommit)
            }
        }

        Task { @MainActor [weak self] in
            await self?.refresh(reason: .initialLoad)
        }
    }

    public func stopObserving() {
        isObserving = false

        guard let transcriptCommitObservation else {
            return
        }

        notificationCenter.removeObserver(transcriptCommitObservation)
        self.transcriptCommitObservation = nil
    }

    isolated deinit {
        if let transcriptCommitObservation {
            notificationCenter.removeObserver(transcriptCommitObservation)
        }
    }

    private func apply(snapshot: MetricsSnapshot) {
        rollups = snapshot.rollups
        recentTranscriptions = snapshot.recentTranscriptions
        lastUpdatedAt = snapshot.lastUpdatedAt
        lastRefreshReason = snapshot.lastRefreshReason
    }
}
