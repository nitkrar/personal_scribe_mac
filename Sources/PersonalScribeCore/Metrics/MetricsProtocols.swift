import Foundation

public protocol MetricsReading: Sendable {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]
}

public protocol MetricsService: Sendable {
    func recordingsThisWeek() async throws -> Int
    func wordsThisWeek() async throws -> Int
    func minsSavedThisWeek() async throws -> Duration
    func wpmAverageThisWeek() async throws -> Double
    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry]
}
