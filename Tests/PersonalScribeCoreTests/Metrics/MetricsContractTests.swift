import Foundation
import XCTest
@testable import PersonalScribeCore

final class MetricsContractTests: XCTestCase {
    func testMetricsContractsAcceptScriptedConformers() async throws {
        let window = MetricsWindow(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let entry = makeMetricsTestEntry(
            timestamp: Date(timeIntervalSince1970: 150),
            text: "hello metrics",
            audioDuration: 30
        )
        let snapshot = makeMetricsSnapshot(
            window: window,
            recordings: 1,
            words: 2,
            minutesSaved: 2,
            averageWPM: 4,
            recentTranscriptions: [entry],
            lastUpdatedAt: Date(timeIntervalSince1970: 200),
            lastRefreshReason: .initialLoad
        )

        let reader: any MetricsReading = ScriptedMetricsReader(
            snapshot: snapshot,
            recentEntries: [entry]
        )
        let service: any MetricsService = ScriptedMetricsService(
            snapshot: snapshot,
            recentEntries: [entry]
        )
        let loadResult = try await reader.loadSnapshot(window: window, recentLimit: 3)
        let readerRecentResult = try await reader.recentTranscriptions(limit: 1)
        let recordings = try await service.recordings(in: window)
        let words = try await service.words(in: window)
        let minutesSaved = try await service.minutesSaved(in: window)
        let averageWPM = try await service.averageWPM(in: window)
        let serviceRecentResult = try await service.recentTranscriptions(limit: 1)

        XCTAssertEqual(loadResult, snapshot)
        XCTAssertEqual(readerRecentResult, [entry])
        XCTAssertEqual(recordings, 1)
        XCTAssertEqual(words, 2)
        XCTAssertEqual(minutesSaved, .seconds(120))
        XCTAssertEqual(averageWPM, 4)
        XCTAssertEqual(serviceRecentResult, [entry])
        XCTAssertEqual(
            MetricsNotification.transcriptCommit,
            Notification.Name("PersonalScribe.metrics.transcriptCommit")
        )
    }

    func testRollingSevenDayWindowAnchorsAtRefreshTime() {
        let calendar = makeMetricsTestCalendar()
        let anchor = Date(timeIntervalSince1970: 10_000)
        let window = MetricsWindow.rollingSevenDays(anchoredAt: anchor, calendar: calendar)

        XCTAssertEqual(window.end, anchor)
        XCTAssertEqual(
            window.start,
            calendar.date(byAdding: .day, value: -7, to: anchor)
        )
    }

    func testMetricsRangesProduceRequestedWindows() {
        let calendar = makeMetricsTestCalendar()
        let anchor = Date(timeIntervalSince1970: 4_000_000)

        XCTAssertEqual(
            MetricsRange.lastSevenDays.window(anchoredAt: anchor, calendar: calendar).start,
            calendar.date(byAdding: .day, value: -7, to: anchor)
        )
        XCTAssertEqual(
            MetricsRange.lastThirtyDays.window(anchoredAt: anchor, calendar: calendar).start,
            calendar.date(byAdding: .day, value: -30, to: anchor)
        )
        XCTAssertEqual(
            MetricsRange.allTime.window(anchoredAt: anchor, calendar: calendar),
            MetricsWindow(start: .distantPast, end: anchor)
        )
    }

    func testMetricsRangePreferenceDefaultsToAllTimeAndPersistsSelection() {
        let suite = "MetricsContractTests.\(#function).\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preference = MetricsRange.preference(defaults: defaults)

        XCTAssertEqual(preference.key, "HomeMetricsRange")
        XCTAssertEqual(preference.resolve(), .allTime)

        preference.persist(.lastThirtyDays)

        XCTAssertEqual(preference.resolve(), .lastThirtyDays)
    }
}
