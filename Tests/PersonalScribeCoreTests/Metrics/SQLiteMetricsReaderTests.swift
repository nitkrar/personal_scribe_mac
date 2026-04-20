import Foundation
import XCTest
@testable import PersonalScribeCore

final class SQLiteMetricsReaderTests: XCTestCase {
    func testLoadSnapshotDerivesRollupsFromEntriesAppendedThroughSQLiteTranscriptStore() async throws {
        let context = try makeMetricsTestDatabaseContext()
        defer { cleanupMetricsTestDatabaseContext(context) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 200_000)
        let window = MetricsWindow.rollingSevenDays(anchoredAt: referenceDate, calendar: calendar)

        let entries = [
            makeMetricsTestEntry(
                timestamp: window.start.addingTimeInterval(-1),
                text: "outside window",
                audioDuration: 15
            ),
            makeMetricsTestEntry(
                timestamp: window.start,
                text: "don't can't",
                audioDuration: 30
            ),
            makeMetricsTestEntry(
                timestamp: referenceDate.addingTimeInterval(-60),
                text: "hello, world!",
                audioDuration: 30
            ),
            makeMetricsTestEntry(
                timestamp: window.end,
                text: "你好 世界",
                audioDuration: 0
            ),
            makeMetricsTestEntry(
                timestamp: window.end.addingTimeInterval(1),
                text: "future row",
                audioDuration: 15
            ),
        ]

        for entry in entries {
            try await store.append(entry)
        }

        let reader = try SQLiteMetricsReader(
            databaseURL: context.databaseURL,
            referenceDateProvider: { referenceDate }
        )
        let snapshot = try await reader.loadSnapshot(window: window, recentLimit: 3)

        XCTAssertEqual(snapshot.rollups.recordingsThisWeek, 3)
        XCTAssertEqual(snapshot.rollups.sampleCount, 3)
        XCTAssertEqual(snapshot.rollups.wordsThisWeek, 8)
        XCTAssertEqual(snapshot.rollups.minutesSavedThisWeek, 0, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rollups.averageWPMThisWeek, 8, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rollups.windowStart, window.start)
        XCTAssertEqual(snapshot.rollups.windowEnd, window.end)
        XCTAssertEqual(snapshot.lastUpdatedAt, referenceDate)
        XCTAssertEqual(snapshot.lastRefreshReason, .initialLoad)
    }

    func testInitThrowsForMissingDatabasePathWhenOpenedReadOnly() throws {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: baseDirectory) }

        let missingDatabaseURL = baseDirectory.appendingPathComponent("missing.sqlite", isDirectory: false)
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDatabaseURL.path))

        XCTAssertThrowsError(try SQLiteMetricsReader(databaseURL: missingDatabaseURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missingDatabaseURL.path))
    }

    func testReadOnlyQueueRejectsWriteAttempts() async throws {
        let context = try makeMetricsTestDatabaseContext()
        defer { cleanupMetricsTestDatabaseContext(context) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let entry = makeMetricsTestEntry(
            timestamp: Date(timeIntervalSince1970: 123),
            text: "readonly probe",
            audioDuration: 5
        )
        try await store.append(entry)

        let reader = try SQLiteMetricsReader(databaseURL: context.databaseURL)

        do {
            try await reader.executeWriteForTesting(sql: "DELETE FROM transcripts")
            XCTFail("Expected readonly write to throw")
        } catch {
            let recent = try await reader.recentTranscriptions(limit: 1)
            XCTAssertEqual(recent, [entry])
        }
    }

    func testLoadSnapshotUsesFortyWPMBaselineForPositiveMinutesSaved() async throws {
        let context = try makeMetricsTestDatabaseContext()
        defer { cleanupMetricsTestDatabaseContext(context) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let referenceDate = Date(timeIntervalSince1970: 300_000)
        let calendar = makeMetricsTestCalendar()
        let window = MetricsWindow.rollingSevenDays(anchoredAt: referenceDate, calendar: calendar)
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-30),
            text: repeatedMetricsWords(120),
            audioDuration: 60
        )

        try await store.append(entry)

        let reader = try SQLiteMetricsReader(
            databaseURL: context.databaseURL,
            referenceDateProvider: { referenceDate }
        )
        let snapshot = try await reader.loadSnapshot(window: window, recentLimit: 3)

        XCTAssertEqual(snapshot.rollups.recordingsThisWeek, 1)
        XCTAssertEqual(snapshot.rollups.wordsThisWeek, 120)
        XCTAssertEqual(snapshot.rollups.minutesSavedThisWeek, 2, accuracy: 0.0001)
        XCTAssertEqual(snapshot.rollups.averageWPMThisWeek, 120, accuracy: 0.0001)
    }

    func testRecentTranscriptionsReturnsNewestFirstWithRequestedLimit() async throws {
        let context = try makeMetricsTestDatabaseContext()
        defer { cleanupMetricsTestDatabaseContext(context) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let baseTimestamp = Date(timeIntervalSince1970: 400_000)
        let older = makeMetricsTestEntry(
            timestamp: baseTimestamp.addingTimeInterval(-180),
            text: "older entry",
            audioDuration: 10
        )
        let middle = makeMetricsTestEntry(
            timestamp: baseTimestamp.addingTimeInterval(-120),
            text: "middle entry",
            audioDuration: 10
        )
        let newer = makeMetricsTestEntry(
            timestamp: baseTimestamp.addingTimeInterval(-60),
            text: "newer entry",
            audioDuration: 10
        )
        let newest = makeMetricsTestEntry(
            timestamp: baseTimestamp,
            text: "newest entry",
            audioDuration: 10
        )

        for entry in [older, middle, newer, newest] {
            try await store.append(entry)
        }

        let reader = try SQLiteMetricsReader(
            databaseURL: context.databaseURL,
            referenceDateProvider: { baseTimestamp }
        )
        let recent = try await reader.recentTranscriptions(limit: 2)
        let snapshot = try await reader.loadSnapshot(
            window: MetricsWindow(
                start: baseTimestamp.addingTimeInterval(-600),
                end: baseTimestamp
            ),
            recentLimit: 3
        )

        XCTAssertEqual(recent, [newest, newer])
        XCTAssertEqual(snapshot.recentTranscriptions, [newest, newer, middle])
    }
}
