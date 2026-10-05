import Foundation
import XCTest
@testable import PersonalScribeCore

@MainActor
final class MetricsSnapshotStoreTests: XCTestCase {
    func testStoreUsesPersistedRangeAndRefreshesWhenSelectionChanges() async throws {
        let defaults = UserDefaults(
            suiteName: "MetricsSnapshotStoreTests.\(#function).\(UUID().uuidString)"
        )!
        MetricsRange.preference(defaults: defaults).persist(.lastThirtyDays)
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 800_000)
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            reader: metricsService,
            calendar: calendar,
            referenceDateProvider: { referenceDate },
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        XCTAssertEqual(store.selectedRange, .lastThirtyDays)

        let firstRefresh = Task { @MainActor in
            await store.refresh(reason: .initialLoad)
        }
        try await waitForCondition(description: "persisted range load") {
            await metricsService.loadRequestCount() == 1
        }
        let firstRequest = await metricsService.loadRequest(at: 0)
        XCTAssertEqual(
            firstRequest.window,
            MetricsRange.lastThirtyDays.window(anchoredAt: referenceDate, calendar: calendar)
        )
        await metricsService.completeNextLoad(
            with: .success(makeMetricsSnapshot(
                window: firstRequest.window,
                recordings: 0,
                words: 0,
                minutesSaved: 0,
                averageWPM: 0,
                recentTranscriptions: [],
                lastUpdatedAt: referenceDate,
                lastRefreshReason: .initialLoad
            ))
        )
        _ = await firstRefresh.value

        let selection = Task { @MainActor in
            await store.selectRange(.lastSevenDays)
        }
        try await waitForCondition(description: "selected range load") {
            await metricsService.loadRequestCount() == 2
        }
        let secondRequest = await metricsService.loadRequest(at: 1)
        XCTAssertEqual(
            secondRequest.window,
            MetricsRange.lastSevenDays.window(anchoredAt: referenceDate, calendar: calendar)
        )
        await metricsService.completeNextLoad(
            with: .success(makeMetricsSnapshot(
                window: secondRequest.window,
                recordings: 0,
                words: 0,
                minutesSaved: 0,
                averageWPM: 0,
                recentTranscriptions: [],
                lastUpdatedAt: referenceDate,
                lastRefreshReason: .rangeChange
            ))
        )
        _ = await selection.value

        XCTAssertEqual(MetricsRange.preference(defaults: defaults).resolve(), .lastSevenDays)
        XCTAssertEqual(store.lastRefreshReason, .rangeChange)
    }

    func testStoreRefreshesOnlyFromExplicitTriggersAndStopsObservingCleanly() async throws {
        let notificationCenter = NotificationCenter()
        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 500_000)
        let window = MetricsRange.lastSevenDays.window(
            anchoredAt: referenceDate,
            calendar: calendar
        )
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-60),
            text: "metrics entry",
            audioDuration: 30
        )
        let initialSnapshot = makeMetricsSnapshot(
            window: window,
            recordings: 1,
            words: 2,
            minutesSaved: 0,
            averageWPM: 4,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .initialLoad
        )
        let commitSnapshot = makeMetricsSnapshot(
            window: window,
            recordings: 2,
            words: 4,
            minutesSaved: 0,
            averageWPM: 8,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate.addingTimeInterval(30),
            lastRefreshReason: .transcriptCommit
        )
        let metricsService = ControllableMetricsService()
        let defaults = UserDefaults(
            suiteName: "MetricsSnapshotStoreTests.\(#function).\(UUID().uuidString)"
        )!
        let store = MetricsSnapshotStore(
            reader: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate },
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        XCTAssertEqual(
            store.rollups,
            MetricsRollups.empty(
                window: MetricsRange.allTime.window(
                    anchoredAt: referenceDate,
                    calendar: calendar
                )
            )
        )
        XCTAssertEqual(store.recentTranscriptions, [TranscriptEntry]())
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
            await store.lastRefreshReason == MetricsRefreshReason.initialLoad
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
            await store.lastRefreshReason == MetricsRefreshReason.transcriptCommit
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
        let window = MetricsRange.lastSevenDays.window(
            anchoredAt: referenceDate,
            calendar: calendar
        )
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-120),
            text: "steady snapshot",
            audioDuration: 60
        )
        let snapshot = makeMetricsSnapshot(
            window: window,
            recordings: 1,
            words: 2,
            minutesSaved: 0,
            averageWPM: 2,
            recentTranscriptions: [entry],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .windowFocus
        )
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            reader: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
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
        let window = MetricsRange.lastSevenDays.window(
            anchoredAt: referenceDate,
            calendar: calendar
        )
        let firstSnapshot = makeMetricsSnapshot(
            window: window,
            recordings: 1,
            words: 10,
            minutesSaved: 0,
            averageWPM: 20,
            recentTranscriptions: [],
            lastUpdatedAt: referenceDate,
            lastRefreshReason: .windowFocus
        )
        let secondSnapshot = makeMetricsSnapshot(
            window: window,
            recordings: 2,
            words: 20,
            minutesSaved: 1,
            averageWPM: 40,
            recentTranscriptions: [],
            lastUpdatedAt: referenceDate.addingTimeInterval(1),
            lastRefreshReason: .transcriptCommit
        )
        let metricsService = ControllableMetricsService()
        let store = MetricsSnapshotStore(
            reader: metricsService,
            notificationCenter: notificationCenter,
            calendar: calendar,
            referenceDateProvider: { referenceDate },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
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

final class SQLiteMetricsServiceAppDatabaseInitTests: XCTestCase {
    func testAllTimeSnapshotIncludesOldEntries() async throws {
        let context = try makeMetricsAppDatabaseContext()
        defer { cleanupMetricsAppDatabaseContext(context) }

        let referenceDate = Date(timeIntervalSince1970: 4_000_000)
        let oldEntry = makeMetricsTestEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: repeatedMetricsWords(40),
            audioDuration: 60
        )
        try await context.repository.append(oldEntry)
        let service = SQLiteMetricsService(
            appDatabase: context.database,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app),
            referenceDateProvider: { referenceDate }
        )

        let snapshot = try await service.loadSnapshot(
            window: MetricsRange.allTime.window(
                anchoredAt: referenceDate,
                calendar: makeMetricsTestCalendar()
            ),
            recentLimit: 3
        )

        XCTAssertEqual(snapshot.rollups.recordings, 1)
        XCTAssertEqual(snapshot.rollups.words, 40)
        XCTAssertEqual(snapshot.recentTranscriptions, [oldEntry])
    }

    func testSnapshotRollupsUseOnlyEntriesInsideRequestedWindow() async throws {
        let context = try makeMetricsAppDatabaseContext()
        defer { cleanupMetricsAppDatabaseContext(context) }

        let referenceDate = Date(timeIntervalSince1970: 3_000_000)
        let inside = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-60),
            text: repeatedMetricsWords(80),
            audioDuration: 60
        )
        let outside = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-40 * 24 * 60 * 60),
            text: repeatedMetricsWords(400),
            audioDuration: 60
        )
        try await context.repository.append(inside)
        try await context.repository.append(outside)
        let service = SQLiteMetricsService(
            appDatabase: context.database,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app),
            referenceDateProvider: { referenceDate }
        )

        let snapshot = try await service.loadSnapshot(
            window: MetricsRange.lastThirtyDays.window(
                anchoredAt: referenceDate,
                calendar: makeMetricsTestCalendar()
            ),
            recentLimit: 3
        )

        XCTAssertEqual(snapshot.rollups.recordings, 1)
        XCTAssertEqual(snapshot.rollups.words, 80)
        XCTAssertEqual(snapshot.rollups.averageWPM, 80)
        XCTAssertEqual(snapshot.rollups.minutesSaved, 1)
        XCTAssertEqual(snapshot.recentTranscriptions, [inside, outside])
    }

    func testServiceConstructedFromAppDatabaseProducesRollupsMatchingRepositoryWrites() async throws {
        let context = try makeMetricsAppDatabaseContext()
        defer { cleanupMetricsAppDatabaseContext(context) }

        let calendar = makeMetricsTestCalendar()
        let referenceDate = Date(timeIntervalSince1970: 310_000)
        let window = MetricsRange.lastSevenDays.window(
            anchoredAt: referenceDate,
            calendar: calendar
        )
        let entry = makeMetricsTestEntry(
            timestamp: referenceDate.addingTimeInterval(-30),
            text: repeatedMetricsWords(80),
            audioDuration: 60
        )

        try await context.repository.append(entry)

        let service = SQLiteMetricsService(
            appDatabase: context.database,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app),
            referenceDateProvider: { referenceDate }
        )

        let snapshot = try await service.loadSnapshot(window: window, recentLimit: 3)
        XCTAssertEqual(snapshot.rollups.recordings, 1)
        XCTAssertEqual(snapshot.rollups.words, 80)
        XCTAssertEqual(snapshot.recentTranscriptions, [entry])

        let recent = try await service.recentTranscriptions(limit: 5)
        XCTAssertEqual(recent, [entry])
    }
}
