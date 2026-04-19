import Foundation
import XCTest
@testable import SeshatCore

@MainActor
final class SQLiteMetricsServiceTests: XCTestCase {
    func testServiceRefreshesOnlyFromExplicitTriggersAndStopsObservingCleanly() async throws {
        let notificationCenter = NotificationCenter()
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 500_000)
        let window = MetricsWindow.rollingSevenDays(anchoredAt: referenceDate, calendar: calendar)
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-60),
            text: "metrics entry",
            audioDuration: 30
        )
        let initialSnapshot = makeMetricsSnapshot(
            window: window,
            recordingsThisWeek: 1,
            wordsThisWeek: 2,
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 4,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .initialLoad
        )
        let commitSnapshot = makeMetricsSnapshot(
            window: window,
            recordingsThisWeek: 2,
            wordsThisWeek: 4,
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 8,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate.addingTimeInterval(30),
            lastRefreshReason: .transcriptCommit
        )
        let reader = ControllableMetricsReader()
        let service = SQLiteMetricsService(
            reader: reader,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        XCTAssertEqual(service.rollups, MetricsRollups.empty(window: window))
        XCTAssertEqual(service.recentTranscriptions, [])
        XCTAssertNil(service.lastUpdatedAt)
        XCTAssertNil(service.lastRefreshReason)
        XCTAssertFalse(service.isRefreshing)

        try await Task.sleep(for: .milliseconds(50))
        let initialLoadCount = await reader.loadRequestCount()
        XCTAssertEqual(initialLoadCount, 0)

        service.startObserving()

        try await waitForCondition(description: "initial load request") {
            await reader.loadRequestCount() == 1
        }
        await reader.completeNextLoad(with: .success(initialSnapshot))
        try await waitForCondition(description: "initial load publish") {
            await service.lastRefreshReason == .initialLoad
        }

        XCTAssertEqual(service.rollups, initialSnapshot.rollups)
        XCTAssertEqual(service.recentTranscriptions, initialSnapshot.recentTranscriptions)
        XCTAssertEqual(service.lastUpdatedAt, referenceDate)
        XCTAssertFalse(service.isRefreshing)

        try await Task.sleep(for: .milliseconds(50))
        let postObserveLoadCount = await reader.loadRequestCount()
        XCTAssertEqual(postObserveLoadCount, 1)

        notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)

        try await waitForCondition(description: "transcript commit refresh") {
            await reader.loadRequestCount() == 2
        }
        await reader.completeNextLoad(with: .success(commitSnapshot))
        try await waitForCondition(description: "commit snapshot publish") {
            await service.lastRefreshReason == .transcriptCommit
        }

        XCTAssertEqual(service.rollups, commitSnapshot.rollups)
        XCTAssertEqual(service.lastUpdatedAt, referenceDate)

        service.stopObserving()
        notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        let postStopLoadCount = await reader.loadRequestCount()
        XCTAssertEqual(postStopLoadCount, 2)
    }

    func testServicePreservesLastGoodSnapshotWhenReadFails() async throws {
        let notificationCenter = NotificationCenter()
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 600_000)
        let window = MetricsWindow.rollingSevenDays(anchoredAt: referenceDate, calendar: calendar)
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-120),
            text: "steady snapshot",
            audioDuration: 60
        )
        let snapshot = makeMetricsSnapshot(
            window: window,
            recordingsThisWeek: 1,
            wordsThisWeek: 2,
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 2,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .windowFocus
        )
        let reader = ControllableMetricsReader()
        let service = SQLiteMetricsService(
            reader: reader,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        let firstRefresh = Task { @MainActor in
            await service.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "window focus refresh request") {
            await reader.loadRequestCount() == 1
        }
        await reader.completeNextLoad(with: .success(snapshot))
        _ = await firstRefresh.value

        let secondRefresh = Task { @MainActor in
            await service.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "failed refresh request") {
            await reader.loadRequestCount() == 2
        }
        await reader.completeNextLoad(with: .failure(StubReadError()))
        _ = await secondRefresh.value

        XCTAssertEqual(service.rollups, snapshot.rollups)
        XCTAssertEqual(service.recentTranscriptions, snapshot.recentTranscriptions)
        XCTAssertEqual(service.lastUpdatedAt, referenceDate)
        XCTAssertEqual(service.lastRefreshReason, .windowFocus)
        XCTAssertFalse(service.isRefreshing)
    }

    func testServiceCoalescesOverlappingRefreshRequests() async throws {
        let notificationCenter = NotificationCenter()
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 700_000)
        let window = MetricsWindow.rollingSevenDays(anchoredAt: referenceDate, calendar: calendar)
        let firstSnapshot = makeMetricsSnapshot(
            window: window,
            recordingsThisWeek: 1,
            wordsThisWeek: 10,
            minutesSavedThisWeek: 0,
            averageWPMThisWeek: 20,
            recentTranscriptions: [],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .windowFocus
        )
        let secondSnapshot = makeMetricsSnapshot(
            window: window,
            recordingsThisWeek: 2,
            wordsThisWeek: 20,
            minutesSavedThisWeek: 1,
            averageWPMThisWeek: 40,
            recentTranscriptions: [],
            lastUpdatedAt: referenceDate.addingTimeInterval(1),
            lastRefreshReason: .transcriptCommit
        )
        let reader = ControllableMetricsReader()
        let service = SQLiteMetricsService(
            reader: reader,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        let firstRefresh = Task { @MainActor in
            await service.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "first refresh request") {
            await reader.loadRequestCount() == 1
        }

        let overlappingWindowFocus = Task { @MainActor in
            await service.refresh(reason: .windowFocus)
        }
        let overlappingCommit = Task { @MainActor in
            await service.refresh(reason: .transcriptCommit)
        }

        await reader.completeNextLoad(with: .success(firstSnapshot))
        try await waitForCondition(description: "coalesced second refresh request") {
            await reader.loadRequestCount() == 2
        }
        await reader.completeNextLoad(with: .success(secondSnapshot))

        _ = await firstRefresh.value
        _ = await overlappingWindowFocus.value
        _ = await overlappingCommit.value

        let overlappingLoadCount = await reader.loadRequestCount()
        XCTAssertEqual(overlappingLoadCount, 2)
        XCTAssertEqual(service.rollups, secondSnapshot.rollups)
        XCTAssertEqual(service.lastRefreshReason, .transcriptCommit)
        XCTAssertFalse(service.isRefreshing)
    }
}

private struct StubReadError: Error {}
