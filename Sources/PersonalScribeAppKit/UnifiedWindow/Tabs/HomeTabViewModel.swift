import Foundation
import PersonalScribeCore

/// View model for the unified-window Home tab (M3.5).
///
/// Owns published `rollups`, `recent`, and `lastRefreshReason` projected
/// from an injected `MetricsReading`. The Home tab consumes the existing
/// L8 Metrics layer verbatim — no rollup recomputation here.
///
/// Reference: `plans/App UI design/Claude_Final_Bundle_Prompt.md` §3A —
/// "Header 'Home'. 4 stat cards (Words this week, Recordings, Mins
/// saved, WPM avg). Recent: A shortened list of the 3 most recent
/// transcriptions."
///
/// The view subscribes to `MetricsNotification.transcriptCommit` and
/// drives `refresh()` whenever a new transcript lands.
@MainActor
public final class HomeTabViewModel: ObservableObject {
    /// Fixed recent-3 list per the reference spec.
    public static let recentLimit: Int = 3

    /// Rolling-7-day rollups (words / recordings / minutes saved / WPM
    /// avg) for the 4 stat cards.
    @Published public private(set) var rollups: MetricsRollups

    /// Most-recent transcripts — bounded to `recentLimit`.
    @Published public private(set) var recent: [TranscriptEntry]

    /// Reason reported by the most recent snapshot refresh. `nil` until
    /// the first `load()` / `refresh()` completes.
    @Published public private(set) var lastRefreshReason: MetricsRefreshReason?

    private let reader: any MetricsReading
    private let calendar: Calendar
    private let referenceDateProvider: @Sendable () -> Date

    public init(
        reader: any MetricsReading,
        calendar: Calendar = .current,
        referenceDateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.reader = reader
        self.calendar = calendar
        self.referenceDateProvider = referenceDateProvider

        let initialWindow = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDateProvider(),
            calendar: calendar
        )
        self.rollups = MetricsRollups.empty(window: initialWindow)
        self.recent = []
        self.lastRefreshReason = nil
    }

    /// Initial load — runs on `.task { ... }`.
    public func load() async {
        await loadSnapshot(reason: .initialLoad)
    }

    /// Reactive refresh — called when the metrics transcript-commit
    /// notification fires or the window regains focus.
    public func refresh(reason: MetricsRefreshReason = .transcriptCommit) async {
        await loadSnapshot(reason: reason)
    }

    private func loadSnapshot(reason: MetricsRefreshReason) async {
        let window = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDateProvider(),
            calendar: calendar
        )
        do {
            let snapshot = try await reader.loadSnapshot(
                window: window,
                recentLimit: Self.recentLimit
            )
            self.rollups = snapshot.rollups
            self.recent = snapshot.recentTranscriptions
            self.lastRefreshReason = reason
        } catch {
            // Swallow — the L8 MetricsSnapshotStore logs the error when
            // the same reader fails there. Home tab simply keeps its
            // previously-published values; the next refresh cycle will
            // retry. We still publish the attempted reason so the UI
            // can surface a "last refresh reason" telemetry state.
            self.lastRefreshReason = reason
        }
    }
}
