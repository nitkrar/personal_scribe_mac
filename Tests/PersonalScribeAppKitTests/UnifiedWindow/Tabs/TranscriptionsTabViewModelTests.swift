import Foundation
import PersonalScribeCore
import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class TranscriptionsTabViewModelTests: XCTestCase {
    // MARK: - Fixtures

    /// Fixed pinned clock — 2026-04-20 12:00:00 local time.
    /// Using `en_US_POSIX` + GMT for deterministic bucket-label
    /// formatting independent of the host locale/time zone.
    private var testCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private func makeNow() -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 4
        components.day = 20
        components.hour = 12
        components.minute = 0
        components.second = 0
        return testCalendar.date(from: components)!
    }

    private func makeEntry(
        id: UUID = UUID(),
        text: String,
        timestamp: Date,
        audioFilename: String? = nil
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: 3.0,
            processingDuration: 0.5,
            audioFilename: audioFilename
        )
    }

    private func makeViewModel(
        entries: [TranscriptEntry] = [],
        now: Date? = nil,
        offlineRetranscriptionAction: OfflineRetranscriptionAction? = nil,
        notificationCenter: NotificationCenter = .default
    ) -> TranscriptionsTabViewModel {
        let fixedNow = now ?? makeNow()
        let store = InlineFakeTranscriptStore(entries: entries)
        return TranscriptionsTabViewModel(
            reader: store,
            offlineRetranscriptionAction: offlineRetranscriptionAction,
            clock: { fixedNow },
            calendar: testCalendar,
            locale: Locale(identifier: "en_US_POSIX"),
            notificationCenter: notificationCenter
        )
    }

    private func makeHarness(
        entries: [TranscriptEntry] = [],
        now: Date? = nil,
        offlineRetranscriptionAction: OfflineRetranscriptionAction? = nil,
        notificationCenter: NotificationCenter = .default
    ) -> (viewModel: TranscriptionsTabViewModel, store: InlineFakeTranscriptStore) {
        let fixedNow = now ?? makeNow()
        let store = InlineFakeTranscriptStore(entries: entries)
        let viewModel = TranscriptionsTabViewModel(
            reader: store,
            offlineRetranscriptionAction: offlineRetranscriptionAction,
            clock: { fixedNow },
            calendar: testCalendar,
            locale: Locale(identifier: "en_US_POSIX"),
            notificationCenter: notificationCenter
        )
        return (viewModel, store)
    }

    // MARK: - Init

    func testInitializesWithEmptyEntriesAndSearch() {
        let viewModel = makeViewModel()
        XCTAssertTrue(viewModel.entries.isEmpty)
        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertTrue(viewModel.filteredEntries.isEmpty)
        XCTAssertTrue(viewModel.groupedByDate.isEmpty)
    }

    // MARK: - load()

    func testLoadPopulatesEntriesFromReader() async {
        let now = makeNow()
        let entry = makeEntry(text: "hello world", timestamp: now)
        let viewModel = makeViewModel(entries: [entry], now: now)

        await viewModel.load()

        XCTAssertEqual(viewModel.entries.count, 1)
        XCTAssertEqual(viewModel.entries.first?.text, "hello world")
    }

    func testDeleteRemovesDeletedEntryFromPublishedEntriesAndDropsCount() async throws {
        let now = makeNow()
        let retained = makeEntry(text: "keep", timestamp: now)
        let deleted = makeEntry(text: "delete", timestamp: now.addingTimeInterval(-60))
        let harness = makeHarness(entries: [retained, deleted], now: now)

        await harness.viewModel.load(limit: 2)
        try await harness.viewModel.delete(id: deleted.id)

        XCTAssertEqual(harness.viewModel.entries.map(\.id), [retained.id])
        XCTAssertEqual(harness.viewModel.entries.count, 1)
        let deletedIDs = await harness.store.deletedIDs()
        XCTAssertEqual(deletedIDs, [deleted.id])
    }

    func testDeleteReloadsFromStoreUsingCurrentLimit() async throws {
        let now = makeNow()
        let newest = makeEntry(text: "newest", timestamp: now)
        let next = makeEntry(text: "next", timestamp: now.addingTimeInterval(-60))
        let older = makeEntry(text: "older", timestamp: now.addingTimeInterval(-120))
        let harness = makeHarness(entries: [newest, next, older], now: now)

        await harness.viewModel.load(limit: 2)
        XCTAssertEqual(harness.viewModel.entries.map(\.id), [newest.id, next.id])

        try await harness.viewModel.delete(id: newest.id)

        XCTAssertEqual(
            harness.viewModel.entries.map(\.id),
            [next.id, older.id],
            "Delete should reload from the store using the active list limit"
        )
    }

    func testUpdateTriggersStoreWriteAndReloadsEditedEntryFromCurrentLimit() async throws {
        let now = makeNow()
        let edited = makeEntry(text: "before", timestamp: now)
        let retained = makeEntry(text: "keep", timestamp: now.addingTimeInterval(-60))
        let harness = makeHarness(entries: [edited, retained], now: now)

        await harness.viewModel.load(limit: 2)
        try await harness.viewModel.update(id: edited.id, text: "after")

        XCTAssertEqual(
            harness.viewModel.entries.map(\.text),
            ["after", "keep"],
            "Update should reload the active storage-backed window after save"
        )
        let updateCalls = await harness.store.updateCalls()
        XCTAssertEqual(updateCalls, [UpdateCall(id: edited.id, text: "after")])
    }

    func testListReloadsOnTranscriptCommitNotification() async throws {
        let now = makeNow()
        let notificationCenter = NotificationCenter()
        let older = makeEntry(
            text: "older",
            timestamp: now.addingTimeInterval(-120)
        )
        let newest = makeEntry(
            text: "newest",
            timestamp: now
        )
        let harness = makeHarness(
            entries: [older],
            now: now,
            notificationCenter: notificationCenter
        )

        await harness.viewModel.load(limit: 1)
        XCTAssertEqual(harness.viewModel.entries.map(\.text), ["older"])

        await harness.store.setEntries([newest, older])
        notificationCenter.post(name: MetricsNotification.transcriptCommit, object: nil)
        try await waitUntil(description: "transcriptions tab reloads on transcript commit") {
            await harness.viewModel.entries.map(\.text) == ["newest"]
        }

        XCTAssertEqual(harness.viewModel.entries.map(\.text), ["newest"])
    }

    func testReTranscribeIconAppearsOnlyForRowsWithAudioFilename() {
        let now = makeNow()
        let withAudio = makeEntry(
            text: "with audio",
            timestamp: now,
            audioFilename: "with-audio.wav"
        )
        let withoutAudio = makeEntry(
            text: "without audio",
            timestamp: now.addingTimeInterval(-60)
        )
        let harness = makeRetranscriptionHarness(entries: [withAudio, withoutAudio], now: now)

        XCTAssertTrue(harness.viewModel.showsRetranscribeIcon(for: withAudio))
        XCTAssertFalse(harness.viewModel.showsRetranscribeIcon(for: withoutAudio))
    }

    func testReTranscribeIconClickInvokesCoordinatorWithRowAudioFilename() async {
        let now = makeNow()
        let entry = makeEntry(
            text: "with audio",
            timestamp: now,
            audioFilename: "row-audio.wav"
        )
        let harness = makeRetranscriptionHarness(entries: [entry], now: now)

        await harness.viewModel.reTranscribe(entry)

        let calls = await harness.coordinator.retranscribeCalls()
        XCTAssertEqual(calls, ["row-audio.wav"])
    }

    func testReTranscribeIconShowsBusyWhileInFlight() async throws {
        let now = makeNow()
        let entry = makeEntry(
            text: "with audio",
            timestamp: now,
            audioFilename: "busy.wav"
        )
        let harness = makeRetranscriptionHarness(entries: [entry], now: now)

        await harness.viewModel.reTranscribe(entry)
        try await waitUntil(description: "offline retranscription observer subscribes") {
            await harness.coordinator.continuationCount() >= 1
        }

        let jobID = await harness.coordinator.nextJobID()
        let inFlightJob = OfflineTranscriptionCoordinator.Job(
            id: jobID,
            url: URL(fileURLWithPath: "/tmp/busy.wav"),
            sourceFilename: "busy.wav",
            descriptorID: "asr-test",
            diarize: false,
            recipeOverride: .fixedDictation,
            enqueuedAt: now,
            status: .inFlight(progress: 0.4)
        )
        await harness.coordinator.emitSnapshot([inFlightJob])

        try await waitUntil(description: "row retranscribe busy state propagates") {
            await harness.viewModel.isRetranscribing(entry)
        }

        XCTAssertTrue(harness.viewModel.isRetranscribing(entry))
    }

    // MARK: - filteredEntries

    func testFilteredEntriesReturnsAllWhenSearchIsEmpty() async {
        let now = makeNow()
        let a = makeEntry(text: "alpha", timestamp: now)
        let b = makeEntry(text: "beta", timestamp: now.addingTimeInterval(-60))
        let viewModel = makeViewModel(entries: [a, b], now: now)

        await viewModel.load()

        XCTAssertEqual(viewModel.searchText, "")
        XCTAssertEqual(viewModel.filteredEntries.count, 2)
    }

    func testFilteredEntriesFiltersCaseInsensitively() async {
        let now = makeNow()
        let match = makeEntry(text: "moon meeting", timestamp: now)
        let noMatch = makeEntry(text: "grocery list", timestamp: now.addingTimeInterval(-60))
        let viewModel = makeViewModel(entries: [match, noMatch], now: now)

        await viewModel.load()
        viewModel.searchText = "MEETING"

        XCTAssertEqual(viewModel.filteredEntries.count, 1)
        XCTAssertEqual(viewModel.filteredEntries.first?.text, "moon meeting")
    }

    // MARK: - groupedByDate

    func testGroupedByDateBucketsTodayAsTODAY() async {
        let now = makeNow()
        // 2026-04-20 10:00 — same calendar day as `now`.
        let entryTimestamp = now.addingTimeInterval(-2 * 60 * 60)
        let entry = makeEntry(text: "today entry", timestamp: entryTimestamp)

        let viewModel = makeViewModel(entries: [entry], now: now)
        await viewModel.load()

        let groups = viewModel.groupedByDate
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bucket, "TODAY")
        XCTAssertEqual(groups.first?.entries.map(\.text), ["today entry"])
    }

    func testGroupedByDateBucketsYesterdayAsYESTERDAY() async {
        let now = makeNow()
        // 2026-04-19 12:00 — one calendar day before `now`.
        let entryTimestamp = testCalendar.date(byAdding: .day, value: -1, to: now)!
        let entry = makeEntry(text: "yesterday entry", timestamp: entryTimestamp)

        let viewModel = makeViewModel(entries: [entry], now: now)
        await viewModel.load()

        let groups = viewModel.groupedByDate
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bucket, "YESTERDAY")
        XCTAssertEqual(groups.first?.entries.map(\.text), ["yesterday entry"])
    }

    func testGroupedByDateBucketsOlderAsCompactMonthDay() async {
        // mockup-gap A.2 — older buckets use the compact `MMM d` glyph
        // (e.g. "APR 17"), not the verbose "APRIL 17, 2026".
        let now = makeNow()
        // 2026-04-17 12:00 — 3 days before `now`.
        let entryTimestamp = testCalendar.date(byAdding: .day, value: -3, to: now)!
        let entry = makeEntry(text: "older entry", timestamp: entryTimestamp)

        let viewModel = makeViewModel(entries: [entry], now: now)
        await viewModel.load()

        let groups = viewModel.groupedByDate
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.bucket, "APR 17")
        XCTAssertEqual(groups.first?.entries.map(\.text), ["older entry"])
    }

    func testGroupedByDateOrderIsTodayThenYesterdayThenOlderDescending() async {
        let now = makeNow()

        let todayEntry = makeEntry(
            text: "today",
            timestamp: now.addingTimeInterval(-60 * 30)
        )
        let yesterdayEntry = makeEntry(
            text: "yesterday",
            timestamp: testCalendar.date(byAdding: .day, value: -1, to: now)!
        )
        let threeDaysAgoEntry = makeEntry(
            text: "three days ago",
            timestamp: testCalendar.date(byAdding: .day, value: -3, to: now)!
        )
        let sevenDaysAgoEntry = makeEntry(
            text: "seven days ago",
            timestamp: testCalendar.date(byAdding: .day, value: -7, to: now)!
        )

        // Intentionally shuffled insertion order — grouping must not
        // depend on the reader's returned order.
        let viewModel = makeViewModel(
            entries: [sevenDaysAgoEntry, todayEntry, threeDaysAgoEntry, yesterdayEntry],
            now: now
        )
        await viewModel.load()

        let groups = viewModel.groupedByDate
        XCTAssertEqual(groups.count, 4)
        XCTAssertEqual(groups[0].bucket, "TODAY")
        XCTAssertEqual(groups[1].bucket, "YESTERDAY")
        // Older buckets sorted newest-first, compact `MMM d` glyph
        // (mockup-gap A.2):
        // 2026-04-17 (three days ago) before 2026-04-13 (seven days ago).
        XCTAssertEqual(groups[2].bucket, "APR 17")
        XCTAssertEqual(groups[2].entries.map(\.text), ["three days ago"])
        XCTAssertEqual(groups[3].bucket, "APR 13")
        XCTAssertEqual(groups[3].entries.map(\.text), ["seven days ago"])
    }

    private func makeRetranscriptionHarness(
        entries: [TranscriptEntry] = [],
        now: Date? = nil
    ) -> (
        viewModel: TranscriptionsTabViewModel,
        store: InlineFakeTranscriptStore,
        coordinator: FakeOfflineTranscriptionCoordinator
    ) {
        let fixedNow = now ?? makeNow()
        let store = InlineFakeTranscriptStore(entries: entries)
        let coordinator = FakeOfflineTranscriptionCoordinator()
        let action = OfflineRetranscriptionAction(
            transcriptReader: store,
            coordinator: coordinator,
            toastBroadcaster: ToastBroadcaster(),
            clipboardWriter: { _ in }
        )
        let viewModel = TranscriptionsTabViewModel(
            reader: store,
            offlineRetranscriptionAction: action,
            clock: { fixedNow },
            calendar: testCalendar,
            locale: Locale(identifier: "en_US_POSIX")
        )
        return (viewModel, store, coordinator)
    }
}

// MARK: - Inline fake

/// Minimal transcript store double for M3.2 tests. `recent(limit:)`
/// returns up to `limit` of the current entries while `delete(id:)`
/// / `update(id:text:)` mutate the actor-backed store so the view model can
/// prove it reloaded from storage rather than only editing local cache.
private actor InlineFakeTranscriptStore: TranscriptReading, TranscriptDeleting, TranscriptUpdating {
    private var entries: [TranscriptEntry]
    private var deletedIDsStorage: [UUID] = []
    private var updateCallsStorage: [UpdateCall] = []

    init(entries: [TranscriptEntry]) {
        self.entries = entries
    }

    func setEntries(_ entries: [TranscriptEntry]) {
        self.entries = entries
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(entries.prefix(limit))
    }

    func search(query: String) async -> [TranscriptEntry] {
        entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func all() async -> [TranscriptEntry] {
        entries
    }

    func delete(id: UUID) async throws {
        deletedIDsStorage.append(id)
        entries.removeAll { $0.id == id }
    }

    func update(id: UUID, text: String) async throws {
        updateCallsStorage.append(UpdateCall(id: id, text: text))
        guard let index = entries.firstIndex(where: { $0.id == id }) else {
            return
        }
        let current = entries[index]
        entries[index] = TranscriptEntry(
            id: current.id,
            timestamp: current.timestamp,
            text: text,
            audioDuration: current.audioDuration,
            processingDuration: current.processingDuration
        )
    }

    func deletedIDs() async -> [UUID] {
        deletedIDsStorage
    }

    func updateCalls() async -> [UpdateCall] {
        updateCallsStorage
    }
}

private actor FakeOfflineTranscriptionCoordinator: OfflineTranscriptionJobManaging {
    private let fixedJobID = UUID()
    private var jobs: [OfflineTranscriptionCoordinator.Job] = []
    private var continuations: [UUID: AsyncStream<[OfflineTranscriptionCoordinator.Job]>.Continuation] = [:]
    private var retranscribeCallsStorage: [String] = []

    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        UUID()
    }

    func reTranscribe(sourceFilename: String) async -> UUID {
        retranscribeCallsStorage.append(sourceFilename)
        return fixedJobID
    }

    func cancelJob(id: UUID) async {}

    func dequeueJob(id: UUID) async {}

    func snapshot() async -> [OfflineTranscriptionCoordinator.Job] {
        jobs
    }

    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]> {
        let continuationID = UUID()
        let snapshot = jobs
        return AsyncStream { continuation in
            self.continuations[continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: continuationID)
                }
            }
            continuation.yield(snapshot)
        }
    }

    func emitSnapshot(_ snapshot: [OfflineTranscriptionCoordinator.Job]) {
        jobs = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func retranscribeCalls() -> [String] {
        retranscribeCallsStorage
    }

    func continuationCount() -> Int {
        continuations.count
    }

    func nextJobID() -> UUID {
        fixedJobID
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}

private func waitUntil(
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
}

private struct UpdateCall: Equatable {
    let id: UUID
    let text: String
}
