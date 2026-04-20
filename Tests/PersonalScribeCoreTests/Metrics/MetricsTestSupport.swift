import Foundation
import XCTest
@testable import PersonalScribeCore

struct MetricsTestDatabaseContext {
    let baseDirectory: URL
    let recordingsDirectory: URL
    let databaseURL: URL
}

func makeMetricsTestDatabaseContext() throws -> MetricsTestDatabaseContext {
    let baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(
        at: baseDirectory,
        withIntermediateDirectories: true
    )

    return MetricsTestDatabaseContext(
        baseDirectory: baseDirectory,
        recordingsDirectory: baseDirectory,
        databaseURL: baseDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
    )
}

func cleanupMetricsTestDatabaseContext(_ context: MetricsTestDatabaseContext) {
    try? FileManager.default.removeItem(at: context.baseDirectory)
}

func makeMetricsTestEntry(
    timestamp: Date,
    text: String,
    audioDuration: TimeInterval,
    processingDuration: TimeInterval = 0.1
) -> TranscriptEntry {
    TranscriptEntry(
        id: UUID(),
        timestamp: timestamp,
        text: text,
        audioDuration: audioDuration,
        processingDuration: processingDuration
    )
}

func repeatedMetricsWords(_ count: Int, word: String = "word") -> String {
    Array(repeating: word, count: count).joined(separator: " ")
}

func makeMetricsTestCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    return calendar
}

func makeMetricsRollups(
    recordingsThisWeek: Int,
    wordsThisWeek: Int,
    minutesSavedThisWeek: Double,
    averageWPMThisWeek: Double,
    sampleCount: Int,
    window: MetricsWindow
) -> MetricsRollups {
    MetricsRollups(
        recordingsThisWeek: recordingsThisWeek,
        wordsThisWeek: wordsThisWeek,
        minutesSavedThisWeek: minutesSavedThisWeek,
        averageWPMThisWeek: averageWPMThisWeek,
        sampleCount: sampleCount,
        windowStart: window.start,
        windowEnd: window.end
    )
}

func makeMetricsSnapshot(
    window: MetricsWindow,
    recordingsThisWeek: Int,
    wordsThisWeek: Int,
    minutesSavedThisWeek: Double,
    averageWPMThisWeek: Double,
    recentTranscriptions: [TranscriptEntry],
    lastUpdatedAt: Date,
    lastRefreshReason: MetricsRefreshReason
) -> MetricsSnapshot {
    MetricsSnapshot(
        rollups: makeMetricsRollups(
            recordingsThisWeek: recordingsThisWeek,
            wordsThisWeek: wordsThisWeek,
            minutesSavedThisWeek: minutesSavedThisWeek,
            averageWPMThisWeek: averageWPMThisWeek,
            sampleCount: recordingsThisWeek,
            window: window
        ),
        recentTranscriptions: recentTranscriptions,
        lastUpdatedAt: lastUpdatedAt,
        lastRefreshReason: lastRefreshReason
    )
}

func waitForCondition(
    description: String,
    timeout: Duration = .seconds(1),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }

        try await Task.sleep(for: pollInterval)
    }

    XCTFail("Timed out waiting for condition: \(description)")
    throw WaitForConditionTimeout(description: description)
}

struct ScriptedMetricsReader: MetricsReading {
    let snapshot: MetricsSnapshot
    let recentEntries: [TranscriptEntry]

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        snapshot
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
    }
}

struct ScriptedMetricsService: MetricsSnapshotLoading {
    let snapshot: MetricsSnapshot
    let recentEntries: [TranscriptEntry]

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        snapshot
    }

    func recordingsThisWeek() async throws -> Int {
        snapshot.rollups.recordingsThisWeek
    }

    func wordsThisWeek() async throws -> Int {
        snapshot.rollups.wordsThisWeek
    }

    func minsSavedThisWeek() async throws -> Duration {
        .seconds(snapshot.rollups.minutesSavedThisWeek * 60)
    }

    func wpmAverageThisWeek() async throws -> Double {
        snapshot.rollups.averageWPMThisWeek
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
    }
}

actor ControllableMetricsService: MetricsSnapshotLoading {
    private var loadRequests: [(window: MetricsWindow, recentLimit: Int)] = []
    private var loadContinuations: [CheckedContinuation<MetricsSnapshot, Error>] = []

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        loadRequests.append((window: window, recentLimit: recentLimit))
        return try await withCheckedThrowingContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func recordingsThisWeek() async throws -> Int {
        throw UnexpectedMetricsQueryInvocation()
    }

    func wordsThisWeek() async throws -> Int {
        throw UnexpectedMetricsQueryInvocation()
    }

    func minsSavedThisWeek() async throws -> Duration {
        throw UnexpectedMetricsQueryInvocation()
    }

    func wpmAverageThisWeek() async throws -> Double {
        throw UnexpectedMetricsQueryInvocation()
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        throw UnexpectedMetricsQueryInvocation()
    }

    func loadRequestCount() -> Int {
        loadRequests.count
    }

    func loadRequest(at index: Int) -> (window: MetricsWindow, recentLimit: Int) {
        loadRequests[index]
    }

    func completeNextLoad(with result: Result<MetricsSnapshot, Error>) {
        guard !loadContinuations.isEmpty else {
            return
        }

        let continuation = loadContinuations.removeFirst()
        switch result {
        case .success(let snapshot):
            continuation.resume(returning: snapshot)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private struct WaitForConditionTimeout: Error {
    let description: String
}

private struct UnexpectedMetricsQueryInvocation: Error {}
