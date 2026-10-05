import Combine
import Foundation

@MainActor
public final class MetricsSnapshotStore: ObservableObject, @unchecked Sendable {
    @Published public private(set) var rollups: MetricsRollups
    @Published public private(set) var recentTranscriptions: [TranscriptEntry]
    @Published public private(set) var lastUpdatedAt: Date?
    @Published public private(set) var lastRefreshReason: MetricsRefreshReason?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var selectedRange: MetricsRange

    private let reader: any MetricsReading
    private let notificationCenter: NotificationCenter
    private let calendar: Calendar
    private let referenceDateProvider: @Sendable () -> Date
    private let recentLimit: Int
    private let logger: PersonalScribeLogger
    private let rangePreference: Preference<MetricsRange>
    private var transcriptCommitObservation: NSObjectProtocol?
    private var pendingRefreshReason: MetricsRefreshReason?
    private var isObserving = false

    public init(
        reader: any MetricsReading,
        notificationCenter: NotificationCenter = .default,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init,
        recentLimit: Int = SQLiteMetricsService.defaultRecentLimit,
        defaults: UserDefaults = .standard,
        logger: PersonalScribeLogger
    ) {
        self.reader = reader
        self.notificationCenter = notificationCenter
        self.calendar = calendar
        self.referenceDateProvider = referenceDateProvider
        self.recentLimit = max(0, recentLimit)
        self.logger = logger
        let rangePreference = MetricsRange.preference(defaults: defaults)
        let selectedRange = rangePreference.resolve()
        self.rangePreference = rangePreference
        self.selectedRange = selectedRange

        let initialWindow = selectedRange.window(
            anchoredAt: referenceDateProvider(), calendar: calendar
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

    public func selectRange(_ range: MetricsRange) async {
        guard selectedRange != range else {
            return
        }
        selectedRange = range
        rangePreference.persist(range)
        await refresh(reason: .rangeChange)
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
        let window = selectedRange.window(anchoredAt: refreshedAt, calendar: calendar)

        let snapshot = try await reader.loadSnapshot(window: window, recentLimit: recentLimit)
        return MetricsSnapshot(
            rollups: snapshot.rollups,
            recentTranscriptions: snapshot.recentTranscriptions,
            lastUpdatedAt: refreshedAt,
            lastRefreshReason: reason
        )
    }

    private func apply(snapshot: MetricsSnapshot) {
        rollups = snapshot.rollups
        recentTranscriptions = snapshot.recentTranscriptions
        lastUpdatedAt = snapshot.lastUpdatedAt
        lastRefreshReason = snapshot.lastRefreshReason
    }
}
