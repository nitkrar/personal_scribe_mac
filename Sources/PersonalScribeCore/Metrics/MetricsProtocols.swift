import Foundation

public protocol MetricsReading: Sendable {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]
}

public protocol MetricsService: Sendable {
    func recordings(in window: MetricsWindow) async throws -> Int
    func words(in window: MetricsWindow) async throws -> Int
    func minutesSaved(in window: MetricsWindow) async throws -> Duration
    func averageWPM(in window: MetricsWindow) async throws -> Double
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]
}
