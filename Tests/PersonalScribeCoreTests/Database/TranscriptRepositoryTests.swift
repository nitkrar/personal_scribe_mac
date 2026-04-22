import Foundation
import XCTest
@testable import PersonalScribeCore

/// CRUD-surface tests for `TranscriptRepository`. Uses a real on-disk
/// `AppDatabase` against a per-test temp directory (follows
/// `AppDatabaseInitTests` pattern). Each test builds a fresh repository so
/// there is no `setUp` leakage and no singleton sharing.
final class TranscriptRepositoryTests: XCTestCase {
    private let fileManager = FileManager.default

    // MARK: - append

    func test_append_persistsEntryFetchableViaRecent() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let entries = [
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "first"),
            makeEntry(timestamp: Date(timeIntervalSince1970: 200), text: "second"),
            makeEntry(timestamp: Date(timeIntervalSince1970: 300), text: "third"),
        ]
        for entry in entries {
            try await harness.repository.append(entry)
        }

        let recent = await harness.repository.recent(limit: 10)

        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.text), ["third", "second", "first"])
    }

    func test_append_wrapsGRDBFailureInTranscriptStorageError() async throws {
        // Failure injection via duplicate PRIMARY KEY: insert the same `id`
        // twice and expect the second append to surface
        // `TranscriptStorageError.queryFailed(underlying:)`.
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let duplicateID = UUID()
        let first = makeEntry(id: duplicateID, timestamp: Date(timeIntervalSince1970: 100), text: "a")
        let second = makeEntry(id: duplicateID, timestamp: Date(timeIntervalSince1970: 200), text: "b")

        try await harness.repository.append(first)

        do {
            try await harness.repository.append(second)
            XCTFail("Expected duplicate-PK insert to throw")
        } catch let error as TranscriptStorageError {
            guard case .queryFailed = error else {
                XCTFail("Expected .queryFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected TranscriptStorageError.queryFailed, got \(error)")
        }
    }

    // MARK: - delete

    func test_delete_removesEntryAndFreshRepositoryReadDoesNotResurrectIt() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let retained = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "keep")
        let deleted = makeEntry(timestamp: Date(timeIntervalSince1970: 200), text: "delete")

        try await harness.repository.append(retained)
        try await harness.repository.append(deleted)

        try await harness.repository.delete(id: deleted.id)

        let remaining = await harness.repository.all()
        XCTAssertEqual(
            remaining.map(\.id),
            [retained.id],
            "Delete should remove the row from the current repository view"
        )

        let recordings = harness.base.appendingPathComponent("recordings", isDirectory: true)
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: harness.base,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let reopenedDatabase = try AppDatabase(locator: locator)
        let reopenedRepository = TranscriptRepository(database: reopenedDatabase)

        let reopenedEntries = await reopenedRepository.all()
        XCTAssertEqual(
            reopenedEntries.map(\.id),
            [retained.id],
            "Deleted row should stay gone after reopening the repository"
        )
    }

    func test_delete_postsTranscriptCommitNotificationOnce() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let notificationCenter = NotificationCenter()
        let repository = TranscriptRepository(
            database: harness.database,
            notificationCenter: notificationCenter
        )
        let entry = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "delete me")
        try await repository.append(entry)

        let expectation = expectation(description: "delete posts metrics refresh notification")
        expectation.assertForOverFulfill = true
        let token = notificationCenter.addObserver(
            forName: MetricsNotification.transcriptCommit,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { notificationCenter.removeObserver(token) }

        try await repository.delete(id: entry.id)

        await fulfillment(of: [expectation], timeout: 1.0)
    }

    // MARK: - recent

    func test_recent_limitZero_returnsEmpty() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        for offset in 1...3 {
            try await harness.repository.append(
                makeEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(offset) * 100), text: "t\(offset)")
            )
        }

        let result = await harness.repository.recent(limit: 0)

        XCTAssertEqual(result, [])
    }

    func test_recent_limitNegative_returnsEmpty() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        for offset in 1...3 {
            try await harness.repository.append(
                makeEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(offset) * 100), text: "t\(offset)")
            )
        }

        let result = await harness.repository.recent(limit: -5)

        XCTAssertEqual(result, [])
    }

    // MARK: - count

    func test_count_reflectsAppends() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        for offset in 1...5 {
            try await harness.repository.append(
                makeEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(offset) * 100), text: "t\(offset)")
            )
        }

        let count = await harness.repository.count()

        XCTAssertEqual(count, 5)
    }

    // MARK: - search

    func test_search_findsFTSMatches() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let hello = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "hello world")
        let goodbye = makeEntry(timestamp: Date(timeIntervalSince1970: 200), text: "goodbye")
        try await harness.repository.append(hello)
        try await harness.repository.append(goodbye)

        let helloMatches = await harness.repository.search(query: "hello")
        XCTAssertEqual(helloMatches.map(\.id), [hello.id])

        let xyzMatches = await harness.repository.search(query: "xyz")
        XCTAssertTrue(xyzMatches.isEmpty, "Expected no matches for 'xyz', got \(xyzMatches.map(\.text))")
    }

    func test_search_emptyQuery_returnsEmpty() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        for offset in 1...3 {
            try await harness.repository.append(
                makeEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(offset) * 100), text: "t\(offset)")
            )
        }

        let emptyResult = await harness.repository.search(query: "")
        let whitespaceResult = await harness.repository.search(query: "   ")

        XCTAssertEqual(emptyResult, [])
        XCTAssertEqual(whitespaceResult, [])
    }

    // MARK: - all

    func test_all_returnsAllNewestFirst() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let a = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "a")
        let b = makeEntry(timestamp: Date(timeIntervalSince1970: 200), text: "b")
        let c = makeEntry(timestamp: Date(timeIntervalSince1970: 300), text: "c")
        // Insert out of order to prove ordering is from the query, not insertion.
        try await harness.repository.append(b)
        try await harness.repository.append(a)
        try await harness.repository.append(c)

        let result = await harness.repository.all()

        XCTAssertEqual(result.map(\.text), ["c", "b", "a"])
    }

    // MARK: - entries(in:orderedBy:)

    func test_entries_inWindow_ascending_returnsRangeSortedAscending() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let entries = try await seedStaircase(repository: harness.repository)

        let window = Date(timeIntervalSince1970: 20)...Date(timeIntervalSince1970: 40)
        let result = await harness.repository.entries(in: window, orderedBy: .timestampAscending)

        XCTAssertEqual(
            result.map(\.id),
            [entries[1].id, entries[2].id, entries[3].id],
            "Expected entries at t=20, 30, 40 in ascending order"
        )
    }

    func test_entries_inWindow_descending_returnsRangeSortedDescending() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let entries = try await seedStaircase(repository: harness.repository)

        let window = Date(timeIntervalSince1970: 20)...Date(timeIntervalSince1970: 40)
        let result = await harness.repository.entries(in: window, orderedBy: .timestampDescending)

        XCTAssertEqual(
            result.map(\.id),
            [entries[3].id, entries[2].id, entries[1].id],
            "Expected entries at t=40, 30, 20 in descending order"
        )
    }

    func test_entries_emptyWindow_returnsEmpty() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        for offset in 1...3 {
            try await harness.repository.append(
                makeEntry(timestamp: Date(timeIntervalSince1970: TimeInterval(offset) * 10), text: "t\(offset)")
            )
        }

        let window = Date(timeIntervalSince1970: 100)...Date(timeIntervalSince1970: 200)
        let result = await harness.repository.entries(in: window, orderedBy: .timestampAscending)

        XCTAssertEqual(result, [])
    }

    // MARK: - Helpers

    private struct Harness {
        let database: AppDatabase
        let repository: TranscriptRepository
        let base: URL
    }

    private func makeHarness() throws -> Harness {
        let (recordings, base) = try makeTempRecordingsDir()
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: base,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let database = try AppDatabase(locator: locator)
        let repository = TranscriptRepository(database: database)
        return Harness(database: database, repository: repository, base: base)
    }

    private func makeTempRecordingsDir() throws -> (recordings: URL, base: URL) {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        let recordings = base.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: recordings, withIntermediateDirectories: true)
        return (recordings, base)
    }

    private func cleanup(_ base: URL) {
        try? fileManager.removeItem(at: base)
    }

    private func makeEntry(
        id: UUID = UUID(),
        timestamp: Date,
        text: String,
        audioDuration: TimeInterval = 1.0,
        processingDuration: TimeInterval = 0.1
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: audioDuration,
            processingDuration: processingDuration
        )
    }

    /// Seeds 5 entries at t=10, 20, 30, 40, 50 (seconds since epoch) and
    /// returns them in insertion order so callers can index into them.
    private func seedStaircase(repository: TranscriptRepository) async throws -> [TranscriptEntry] {
        let timestamps: [TimeInterval] = [10, 20, 30, 40, 50]
        var entries: [TranscriptEntry] = []
        for t in timestamps {
            let entry = makeEntry(timestamp: Date(timeIntervalSince1970: t), text: "t=\(Int(t))")
            try await repository.append(entry)
            entries.append(entry)
        }
        return entries
    }
}
