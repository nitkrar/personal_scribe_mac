import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class HomeTabViewModelTests: XCTestCase {
    // MARK: - Initialization

    func testInitializesWithEmptyRollupsAndRecent() {
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: Self.rollups(recordings: 7, words: 42, minutes: 3, wpm: 100),
            recent: [Self.transcript(text: "one")]
        ))
        let viewModel = HomeTabViewModel(
            reader: reader,
            referenceDateProvider: { Self.referenceDate }
        )

        XCTAssertEqual(viewModel.rollups.recordingsThisWeek, 0)
        XCTAssertEqual(viewModel.rollups.wordsThisWeek, 0)
        XCTAssertEqual(viewModel.rollups.minutesSavedThisWeek, 0)
        XCTAssertEqual(viewModel.rollups.averageWPMThisWeek, 0)
        XCTAssertTrue(viewModel.recent.isEmpty)
        XCTAssertNil(viewModel.lastRefreshReason)
        XCTAssertEqual(reader.loadCallCount, 0)
    }

    // MARK: - Load populates rollups

    func testLoadPopulatesRollupsFromReader() async {
        let seededRollups = Self.rollups(
            recordings: 5,
            words: 1234,
            minutes: 17.25,
            wpm: 128.4
        )
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: seededRollups,
            recent: []
        ))
        let viewModel = HomeTabViewModel(
            reader: reader,
            referenceDateProvider: { Self.referenceDate }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.rollups.recordingsThisWeek, 5)
        XCTAssertEqual(viewModel.rollups.wordsThisWeek, 1234)
        XCTAssertEqual(viewModel.rollups.minutesSavedThisWeek, 17.25, accuracy: 0.0001)
        XCTAssertEqual(viewModel.rollups.averageWPMThisWeek, 128.4, accuracy: 0.0001)
        XCTAssertEqual(viewModel.lastRefreshReason, .initialLoad)
    }

    // MARK: - Load populates recent transcripts

    func testLoadPopulatesRecentFromReader() async {
        let transcripts = [
            Self.transcript(text: "one"),
            Self.transcript(text: "two"),
            Self.transcript(text: "three"),
        ]
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: Self.rollups(),
            recent: transcripts
        ))
        let viewModel = HomeTabViewModel(
            reader: reader,
            referenceDateProvider: { Self.referenceDate }
        )

        await viewModel.load()

        XCTAssertEqual(viewModel.recent.map(\.text), ["one", "two", "three"])
    }

    // MARK: - Reader called with recentLimit == 3

    func testLoadCallsReaderWithRecentLimitOfThree() async {
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: Self.rollups(),
            recent: []
        ))
        let viewModel = HomeTabViewModel(
            reader: reader,
            referenceDateProvider: { Self.referenceDate }
        )

        await viewModel.load()

        XCTAssertEqual(reader.loadCallCount, 1)
        XCTAssertEqual(reader.lastRecentLimit, HomeTabViewModel.recentLimit)
        XCTAssertEqual(reader.lastRecentLimit, 3)
    }

    // MARK: - Refresh reloads

    func testRefreshReloadsViaReader() async {
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: Self.rollups(),
            recent: []
        ))
        let viewModel = HomeTabViewModel(
            reader: reader,
            referenceDateProvider: { Self.referenceDate }
        )

        await viewModel.load()
        XCTAssertEqual(reader.loadCallCount, 1)
        XCTAssertEqual(viewModel.lastRefreshReason, .initialLoad)

        await viewModel.refresh()

        XCTAssertEqual(reader.loadCallCount, 2)
        XCTAssertEqual(viewModel.lastRefreshReason, .transcriptCommit)
    }

    // MARK: - Window anchored at reference date

    func testLoadPassesRollingSevenDayWindowAnchoredAtReferenceDate() async {
        let reader = FakeMetricsReading(snapshot: Self.snapshot(
            rollups: Self.rollups(),
            recent: []
        ))
        let calendar = Calendar(identifier: .gregorian)
        let viewModel = HomeTabViewModel(
            reader: reader,
            calendar: calendar,
            referenceDateProvider: { Self.referenceDate }
        )

        await viewModel.load()

        let expected = MetricsWindow.rollingSevenDays(
            anchoredAt: Self.referenceDate,
            calendar: calendar
        )
        XCTAssertEqual(reader.lastWindow?.start, expected.start)
        XCTAssertEqual(reader.lastWindow?.end, expected.end)
    }

    // MARK: - Helpers

    nonisolated private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func rollups(
        recordings: Int = 0,
        words: Int = 0,
        minutes: Double = 0,
        wpm: Double = 0
    ) -> MetricsRollups {
        let window = MetricsWindow.rollingSevenDays(
            anchoredAt: referenceDate,
            calendar: .current
        )
        return MetricsRollups(
            recordingsThisWeek: recordings,
            wordsThisWeek: words,
            minutesSavedThisWeek: minutes,
            averageWPMThisWeek: wpm,
            sampleCount: recordings,
            windowStart: window.start,
            windowEnd: window.end
        )
    }

    private static func snapshot(
        rollups: MetricsRollups,
        recent: [TranscriptEntry]
    ) -> MetricsSnapshot {
        MetricsSnapshot(
            rollups: rollups,
            recentTranscriptions: recent,
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .initialLoad
        )
    }

    private static func transcript(text: String) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: referenceDate,
            text: text,
            audioDuration: 10,
            processingDuration: 1
        )
    }
}

// MARK: - FakeMetricsReading

/// In-test fake that returns a canned `MetricsSnapshot`, tracks how
/// many times `loadSnapshot` was called, and captures the last
/// `window` / `recentLimit` arguments.
///
/// Conforms to `MetricsReading` which is declared `Sendable`. We mark
/// mutable state as `nonisolated(unsafe)` — the tests drive everything
/// from `@MainActor` so there is no real concurrent access.
private final class FakeMetricsReading: MetricsReading, @unchecked Sendable {
    nonisolated(unsafe) var snapshotResult: MetricsSnapshot
    nonisolated(unsafe) var loadCallCount: Int = 0
    nonisolated(unsafe) var lastWindow: MetricsWindow?
    nonisolated(unsafe) var lastRecentLimit: Int?

    init(snapshot: MetricsSnapshot) {
        self.snapshotResult = snapshot
    }

    func loadSnapshot(
        window: MetricsWindow,
        recentLimit: Int
    ) async throws -> MetricsSnapshot {
        loadCallCount += 1
        lastWindow = window
        lastRecentLimit = recentLimit
        return snapshotResult
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] {
        Array(snapshotResult.recentTranscriptions.prefix(limit))
    }
}
