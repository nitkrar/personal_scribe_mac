import Foundation
import XCTest
@testable import SeshatCore

@MainActor
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
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 4,
            recentTranscriptions: [entry],
            lastUpdatedAt: Date(timeIntervalSince1970: 200),
            lastRefreshReason: .initialLoad
        )

        let reader: any MetricsReading = ScriptedMetricsReader(
            snapshot: snapshot,
            recentEntries: [entry]
        )
        let service = ScriptedMetricsService(snapshot: snapshot)
        let loadResult = try await reader.loadSnapshot(window: window, recentLimit: 3)
        let recentResult = try await reader.recentTranscriptions(limit: 1)

        await service.refresh(reason: .windowFocus)
        service.startObserving()
        service.stopObserving()

        XCTAssertEqual(loadResult, snapshot)
        XCTAssertEqual(recentResult, [entry])
        XCTAssertEqual(service.rollups, snapshot.rollups)
        XCTAssertEqual(service.lastRefreshReason, .windowFocus)
        XCTAssertEqual(service.startObservingCount, 1)
        XCTAssertEqual(service.stopObservingCount, 1)
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
