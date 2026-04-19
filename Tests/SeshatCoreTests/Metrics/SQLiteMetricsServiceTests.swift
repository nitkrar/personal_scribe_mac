import Foundation
import XCTest
@testable import SeshatCore

@MainActor
final class MetricsSnapshotStoreTests: XCTestCase {
    func testStoreRefreshesOnlyFromExplicitTriggersAndStopsObservingCleanly() async throws {
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
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            metricsService: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        XCTAssertEqual(store.rollups, MetricsRollups.empty(window: window))
        XCTAssertEqual(store.recentTranscriptions, [])
        XCTAssertNil(store.lastUpdatedAt)
        XCTAssertNil(store.lastRefreshReason)
        XCTAssertFalse(store.isRefreshing)

        try await Task.sleep(for: .milliseconds(50))
        let initialLoadCount = await metricsService.loadRequestCount()
        XCTAssertEqual(initialLoadCount, 0)

        store.startObserving()

        try await waitForCondition(description: "initial load request") {
            await metricsService.loadRequestCount() == 1
        }
        await metricsService.completeNextLoad(with: .success(initialSnapshot))
        try await waitForCondition(description: "initial load publish") {
            await store.lastRefreshReason == .initialLoad
        }

        XCTAssertEqual(store.rollups, initialSnapshot.rollups)
        XCTAssertEqual(store.recentTranscriptions, initialSnapshot.recentTranscriptions)
        XCTAssertEqual(store.lastUpdatedAt, referenceDate)
        XCTAssertFalse(store.isRefreshing)

        try await Task.sleep(for: .milliseconds(50))
        let postObserveLoadCount = await metricsService.loadRequestCount()
        XCTAssertEqual(postObserveLoadCount, 1)

        notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)

        try await waitForCondition(description: "transcript commit refresh") {
            await metricsService.loadRequestCount() == 2
        }
        await metricsService.completeNextLoad(with: .success(commitSnapshot))
        try await waitForCondition(description: "commit snapshot publish") {
            await store.lastRefreshReason == .transcriptCommit
        }

        XCTAssertEqual(store.rollups, commitSnapshot.rollups)
        XCTAssertEqual(store.lastUpdatedAt, referenceDate)

        store.stopObserving()
        notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)
        try await Task.sleep(for: .milliseconds(50))
        let postStopLoadCount = await metricsService.loadRequestCount()
        XCTAssertEqual(postStopLoadCount, 2)
    }

    func testStorePreservesLastGoodSnapshotWhenRefreshFails() async throws {
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
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            metricsService: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        let firstRefresh = Task { @MainActor in
            await store.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "window focus refresh request") {
            await metricsService.loadRequestCount() == 1
        }
        await metricsService.completeNextLoad(with: .success(snapshot))
        _ = await firstRefresh.value

        let secondRefresh = Task { @MainActor in
            await store.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "failed refresh request") {
            await metricsService.loadRequestCount() == 2
        }
        await metricsService.completeNextLoad(with: .failure(StubReadError()))
        _ = await secondRefresh.value

        XCTAssertEqual(store.rollups, snapshot.rollups)
        XCTAssertEqual(store.recentTranscriptions, snapshot.recentTranscriptions)
        XCTAssertEqual(store.lastUpdatedAt, referenceDate)
        XCTAssertEqual(store.lastRefreshReason, .windowFocus)
        XCTAssertFalse(store.isRefreshing)
    }

    func testStoreCoalescesOverlappingRefreshRequests() async throws {
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
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            metricsService: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate }
        )

        let firstRefresh = Task { @MainActor in
            await store.refresh(reason: .windowFocus)
        }
        try await waitForCondition(description: "first refresh request") {
            await metricsService.loadRequestCount() == 1
        }

        let overlappingWindowFocus = Task { @MainActor in
            await store.refresh(reason: .windowFocus)
        }
        let overlappingCommit = Task { @MainActor in
            await store.refresh(reason: .transcriptCommit)
        }

        await metricsService.completeNextLoad(with: .success(firstSnapshot))
        try await waitForCondition(description: "coalesced second refresh request") {
            await metricsService.loadRequestCount() == 2
        }
        await metricsService.completeNextLoad(with: .success(secondSnapshot))

        _ = await firstRefresh.value
        _ = await overlappingWindowFocus.value
        _ = await overlappingCommit.value

        let overlappingLoadCount = await metricsService.loadRequestCount()
        XCTAssertEqual(overlappingLoadCount, 2)
        XCTAssertEqual(store.rollups, secondSnapshot.rollups)
        XCTAssertEqual(store.lastRefreshReason, .transcriptCommit)
        XCTAssertFalse(store.isRefreshing)
    }
}

private struct StubReadError: Error {}
