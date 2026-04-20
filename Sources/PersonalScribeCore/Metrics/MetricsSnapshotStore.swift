import Combine
import Foundation

protocol MetricsSnapshotLoading: MetricsService {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot
}

@MainActor
public final class MetricsSnapshotStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var rollups: MetricsRollups
    @Published public private(set) var recentTranscriptions: [TranscriptEntry]
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var lastRefreshReason: MetricsRefreshReason?
    @Published public private(set) var isRefreshing = false

    private let metricsService: any MetricsService
    private let notificationCenter: NotificationCenter
    private let calendar: Calendar
    private let referenceDateProvider: @Sendable () -> Date
    private let recentLimit: Int
    private let logger: PersonalScribeLogger
    private var transcriptCommitObservation: NSObjectProtocol?
    private var pendingRefreshReason: MetricsRefreshReason?
    private var isObserving = false

    public convenience init(
        databaseURL: URL,
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)
    ) throws {
        let metricsService = try SQLiteMetricsService(
            databaseURL: databaseURL,
            calendar: calendar,
            referenceDateProvider: referenceDateProvider,
            recentLimit: recentLimit
        )
        self.init(
            metricsService: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: referenceDateProvider,
            recentLimit: recentLimit,
            logger: logger
        )
    }

    public init(
        metricsService: any MetricsService,
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.app)
    ) {
        self.metricsService = metricsService
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

            do {
                let snapshot = try await loadSnapshot(
                    refreshedAt: refreshedAt,
                    reason: nextReason
                )
                apply(snapshot: snapshot)
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

    private func loadSnapshot(
        refreshedAt: Date,
        reason: MetricsRefreshReason
    ) async throws -> MetricsSnapshot {
        let window = MetricsWindow.rollingSevenDays(
            anchoredAt: refreshedAt,
            calendar: calendar
        )

        if let snapshotLoader = metricsService as? any MetricsSnapshotLoading {
            let snapshot = try await snapshotLoader.loadSnapshot(
                window: window,
                recentLimit: recentLimit
            )
            return MetricsSnapshot(
                rollups: snapshot.rollups,
                recentTranscriptions: snapshot.recentTranscriptions,
                lastUpdatedAt: refreshedAt,
                lastRefreshReason: reason
            )
        }

        async let recordingsThisWeek = metricsService.recordingsThisWeek()
        async let wordsThisWeek = metricsService.wordsThisWeek()
        async let minsSavedThisWeek = metricsService.minsSavedThisWeek()
        async let averageWPMThisWeek = metricsService.wpmAverageThisWeek()
        async let recentEntries = metricsService.recentTranscriptions(limit: recentLimit)

        let recordings = try await recordingsThisWeek
        let words = try await wordsThisWeek
        let minsSaved = try await minsSavedThisWeek
        let averageWPM = try await averageWPMThisWeek
        let recentTranscriptions = try await recentEntries

        return MetricsSnapshot(
            rollups: MetricsRollups(
                recordingsThisWeek: recordings,
                wordsThisWeek: words,
                minutesSavedThisWeek: Self.minutes(from: minsSaved),
                averageWPMThisWeek: averageWPM,
                sampleCount: recordings,
                windowStart: window.start,
                windowEnd: window.end
            ),
            recentTranscriptions: recentTranscriptions,
            lastUpdatedAt: refreshedAt,
            lastRefreshReason: reason
        )
    }

    private static func minutes(from duration: Duration) -> Double {
        let components = duration.components
        let seconds = Double(components.seconds)
            + Double(components.attoseconds) / 1_000_000_000_000_000_000
        return seconds / 60
    }

    private func apply(snapshot: MetricsSnapshot) {
        rollups = snapshot.rollups
        recentTranscriptions = snapshot.recentTranscriptions
        lastUpdatedAt = snapshot.lastUpdatedAt
        lastRefreshReason = snapshot.lastRefreshReason
    }
}
