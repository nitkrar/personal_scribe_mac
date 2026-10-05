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

struct MetricsAppDatabaseContext {
    let baseDirectory: URL
    let database: AppDatabase
    let repository: TranscriptRepository
}

func makeMetricsAppDatabaseContext() throws -> MetricsAppDatabaseContext {
    let baseDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("MetricsAppDatabase-\(UUID().uuidString)", isDirectory: true)
    let recordingsDirectory = baseDirectory
        .appendingPathComponent("recordings", isDirectory: true)
    try FileManager.default.createDirectory(
        at: recordingsDirectory,
        withIntermediateDirectories: true
    )

    let locator = FixedBaseDirectoryStorageLocator(
        baseDirectory: baseDirectory,
        managedDirectoryOverrides: [.recordings: recordingsDirectory]
    )
    let database = try AppDatabase(locator: locator)
    let repository = TranscriptRepository(
        database: database,
        logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
    )

    return MetricsAppDatabaseContext(
        baseDirectory: baseDirectory,
        database: database,
        repository: repository
    )
}

func cleanupMetricsAppDatabaseContext(_ context: MetricsAppDatabaseContext) {
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
    recordings: Int,
    words: Int,
    minutesSaved: Double,
    averageWPM: Double,
    sampleCount: Int,
    window: MetricsWindow
) -> MetricsRollups {
    MetricsRollups(
        recordings: recordings,
        words: words,
        minutesSaved: minutesSaved,
        averageWPM: averageWPM,
        sampleCount: sampleCount,
        windowStart: window.start,
        windowEnd: window.end
    )
}

func makeMetricsSnapshot(
    window: MetricsWindow,
    recordings: Int,
    words: Int,
    minutesSaved: Double,
    averageWPM: Double,
    recentTranscriptions: [TranscriptEntry],
    lastUpdatedAt: Date,
    lastRefreshReason: MetricsRefreshReason
) -> MetricsSnapshot {
    MetricsSnapshot(
        rollups: makeMetricsRollups(
            recordings: recordings,
            words: words,
            minutesSaved: minutesSaved,
            averageWPM: averageWPM,
            sampleCount: recordings,
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

struct ScriptedMetricsService: MetricsService, MetricsReading {
    let snapshot: MetricsSnapshot
    let recentEntries: [TranscriptEntry]

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        snapshot
    }

    func recordings(in window: MetricsWindow) async throws -> Int {
        snapshot.rollups.recordings
    }

    func words(in window: MetricsWindow) async throws -> Int {
        snapshot.rollups.words
    }

    func minutesSaved(in window: MetricsWindow) async throws -> Duration {
        .seconds(snapshot.rollups.minutesSaved * 60)
    }

    func averageWPM(in window: MetricsWindow) async throws -> Double {
        snapshot.rollups.averageWPM
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
    }
}

actor ControllableMetricsService: MetricsReading {
    private var loadRequests: [(window: MetricsWindow, recentLimit: Int)] = []
    private var loadContinuations: [CheckedContinuation<MetricsSnapshot, Error>] = []

    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        loadRequests.append((window: window, recentLimit: recentLimit))
        return try await withCheckedThrowingContinuation { continuation in
            loadContinuations.append(continuation)
        }
    }

    func recordings(in window: MetricsWindow) async throws -> Int {
        throw UnexpectedMetricsQueryInvocation()
    }

    func words(in window: MetricsWindow) async throws -> Int {
        throw UnexpectedMetricsQueryInvocation()
    }

    func minutesSaved(in window: MetricsWindow) async throws -> Duration {
        throw UnexpectedMetricsQueryInvocation()
    }

    func averageWPM(in window: MetricsWindow) async throws -> Double {
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
