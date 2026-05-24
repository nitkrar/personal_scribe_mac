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

    func test_append_postsTranscriptCommitNotificationOnce() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let notificationCenter = NotificationCenter()
        let repository = TranscriptRepository(
            database: harness.database,
            notificationCenter: notificationCenter,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )
        let expectation = expectation(description: "append posts metrics refresh notification")
        expectation.assertForOverFulfill = true
        let token = notificationCenter.addObserver(
            forName: MetricsNotification.transcriptCommit,
            object: nil,
            queue: nil
        ) { _ in
            expectation.fulfill()
        }
        defer { notificationCenter.removeObserver(token) }

        try await repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "append me")
        )

        await fulfillment(of: [expectation], timeout: 1.0)
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
            remaining.map { $0.id },
            [retained.id],
            "Delete should remove the row from the current repository view"
        )

        let recordings = harness.base.appendingPathComponent("recordings", isDirectory: true)
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: harness.base,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let reopenedDatabase = try AppDatabase(locator: locator)
        let reopenedRepository = TranscriptRepository(
            database: reopenedDatabase,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        let reopenedEntries = await reopenedRepository.all()
        XCTAssertEqual(
            reopenedEntries.map { $0.id },
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
            notificationCenter: notificationCenter,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
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

    func testDeleteRemovesAudioSidecarWhenPresent() async throws {
        let remover = AudioFileRemoverSpy()
        let harness = try makeHarness(audioFileRemover: remover.remove)
        defer { cleanup(harness.base) }

        let entry = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "delete me",
            audioFilename: "20260519_113345.wav"
        )
        try await harness.repository.append(entry)

        try await harness.repository.delete(id: entry.id)

        XCTAssertEqual(remover.calls(), ["20260519_113345.wav"])
    }

    func testDeleteSkipsRemoverWhenAudioFilenameNil() async throws {
        let remover = AudioFileRemoverSpy()
        let harness = try makeHarness(audioFileRemover: remover.remove)
        defer { cleanup(harness.base) }

        let entry = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "delete me")
        try await harness.repository.append(entry)

        try await harness.repository.delete(id: entry.id)

        XCTAssertTrue(remover.calls().isEmpty)
    }

    func testDeleteSucceedsWhenAudioRemovalFails() async throws {
        let sink = InMemoryTestSink()
        let logger = PersonalScribeLogger(
            category: PersonalScribeLogCategory.app,
            reporter: DiagnosticsReporter(sinks: [sink])
        )
        let remover = AudioFileRemoverSpy(error: AudioRemovalFailure.removeFailed)
        let harness = try makeHarness(
            logger: logger,
            audioFileRemover: remover.remove
        )
        defer { cleanup(harness.base) }

        let entry = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "delete me",
            audioFilename: "20260519_113345.wav"
        )
        try await harness.repository.append(entry)

        try await harness.repository.delete(id: entry.id)
        try await waitForDiagnostics(in: sink)

        let remaining = await harness.repository.all()
        let events = await sink.snapshot()

        XCTAssertTrue(remaining.isEmpty)
        XCTAssertEqual(remover.calls(), ["20260519_113345.wav"])
        XCTAssertTrue(
            events.contains { event in
                event.level == .error &&
                event.message == "TranscriptRepository.delete file removal failed" &&
                event.underlyingError?.contains("removeFailed") == true
            }
        )
    }

    // MARK: - update

    func test_update_persistsNewTextReadableFromRepository() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let entry = makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "before")
        try await harness.repository.append(entry)

        try await harness.repository.update(id: entry.id, text: "after")

        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.text, "after")
    }

    func test_update_unknownID_throwsUpdateFailed() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        do {
            try await harness.repository.update(id: UUID(), text: "x")
            XCTFail("Expected update of unknown row to throw")
        } catch let error as TranscriptStorageError {
            guard case .updateFailed = error else {
                XCTFail("Expected .updateFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected TranscriptStorageError.updateFailed, got \(error)")
        }
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

    func testMostRecentEntryWithAudioReturnsNilWhenNoRowsHaveAudio() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        try await harness.repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "first")
        )
        try await harness.repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 200), text: "second")
        )

        let result = await harness.repository.mostRecentEntryWithAudio()

        XCTAssertNil(result)
    }

    func testMostRecentEntryWithAudioReturnsLatestRowWithAudio() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let withAudio = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "with-audio",
            audioFilename: "one.wav"
        )
        let newerWithoutAudio = makeEntry(
            timestamp: Date(timeIntervalSince1970: 200),
            text: "without-audio"
        )
        try await harness.repository.append(withAudio)
        try await harness.repository.append(newerWithoutAudio)

        let result = await harness.repository.mostRecentEntryWithAudio()

        XCTAssertEqual(result?.id, withAudio.id)
    }

    func testMostRecentEntryWithAudioOrdersByTimestampDesc() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let older = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "older",
            audioFilename: "older.wav"
        )
        let newer = makeEntry(
            timestamp: Date(timeIntervalSince1970: 300),
            text: "newer",
            audioFilename: "newer.wav"
        )
        try await harness.repository.append(older)
        try await harness.repository.append(newer)

        let result = await harness.repository.mostRecentEntryWithAudio()

        XCTAssertEqual(result?.id, newer.id)
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

    private func makeHarness(
        logger: PersonalScribeLogger = PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app),
        audioFileRemover: @escaping @Sendable (String) throws -> Void = { _ in }
    ) throws -> Harness {
        let (recordings, base) = try makeTempRecordingsDir()
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: base,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let database = try AppDatabase(locator: locator)
        let repository = TranscriptRepository(
            database: database,
            audioFileRemover: audioFileRemover,
            logger: logger
        )
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
        processingDuration: TimeInterval = 0.1,
        audioFilename: String? = nil
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: audioDuration,
            processingDuration: processingDuration,
            audioFilename: audioFilename
        )
    }

    private func waitForDiagnostics(in sink: InMemoryTestSink) async throws {
        for _ in 0..<100 {
            if await sink.snapshot().isEmpty == false {
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Diagnostics sink never received the delete failure event")
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

private final class AudioFileRemoverSpy: @unchecked Sendable {
    private let lock = NSLock()
    private var removed: [String] = []
    private let error: (any Error)?

    init(error: (any Error)? = nil) {
        self.error = error
    }

    func remove(_ filename: String) throws {
        lock.lock()
        removed.append(filename)
        lock.unlock()

        if let error {
            throw error
        }
    }

    func calls() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return removed
    }
}

private enum AudioRemovalFailure: Error {
    case removeFailed
}
