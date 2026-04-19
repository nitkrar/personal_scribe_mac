import Foundation
import XCTest
@testable import SeshatCore

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
            recordingsThisWeek: 1,
            wordsThisWeek: 2,
            minutesSavedThisWeek: 2,
            averageWPMThisWeek: 4,
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
        let recordingsThisWeek = try await service.recordingsThisWeek()
        let wordsThisWeek = try await service.wordsThisWeek()
        let minsSavedThisWeek = try await service.minsSavedThisWeek()
        let wpmAverageThisWeek = try await service.wpmAverageThisWeek()
        let serviceRecentResult = try await service.recentTranscriptions(limit: 1)

        XCTAssertEqual(loadResult, snapshot)
        XCTAssertEqual(readerRecentResult, [entry])
        XCTAssertEqual(recordingsThisWeek, 1)
        XCTAssertEqual(wordsThisWeek, 2)
        XCTAssertEqual(minsSavedThisWeek, .seconds(120))
        XCTAssertEqual(wpmAverageThisWeek, 4)
        XCTAssertEqual(serviceRecentResult, [entry])
        XCTAssertEqual(
            MetricsNotification.transcriptCommit,
            Notification.Name("Seshat.metrics.transcriptCommit")
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
}
