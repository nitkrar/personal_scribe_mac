import Combine
import Foundation

public protocol MetricsReading: Sendable {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]
}

@MainActor
public protocol MetricsService: ObservableObject, Sendable {
    var rollups: MetricsRollups { get }
    var recentTranscriptions: [TranscriptEntry] { get }
    var lastUpdatedAt: Date? { get }
    var lastRefreshReason: MetricsRefreshReason? { get }
    var isRefreshing: Bool { get }

    func refresh(reason: MetricsRefreshReason) async
    func startObserving()
    func stopObserving()
}
