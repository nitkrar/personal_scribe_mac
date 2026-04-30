import Foundation
import XCTest
@testable import PersonalScribeCore

/// Tests for `DatabaseOperationStatus` + `DatabaseOperationObserver`
/// plumbing through `TranscriptRepository` (backlog #043). Each test
/// builds a fresh real-AppDatabase harness (matching
/// `TranscriptRepositoryTests`) and asserts the observer's published
/// `current` value after the repo operation settles.
///
/// Async-hop note: `DatabaseOperationObserver.record(_:)` is
/// `nonisolated` and spawns a main-actor `Task` to publish — so the
/// `current` value is *not* guaranteed to be updated synchronously
/// after the repo method returns. Tests use `waitForCondition` to poll
/// up to the default 1s deadline.
@MainActor
final class DatabaseOperationStatusTests: XCTestCase {
    private let fileManager = FileManager.default

    // MARK: - Null observer

    func test_null_observer_record_isNoOp() {
        let observer = NullDatabaseOperationObserver()
        // Just confirm every status can be recorded without side effects
        // or crashes.
        observer.record(.idle)
        observer.record(.readSucceeded)
        observer.record(.readFailed)
        observer.record(.writeSucceeded)
        observer.record(.writeFailed)
    }

    // MARK: - Reads

    func test_recent_onPopulatedDB_recordsReadSucceeded() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        try await harness.repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "hello")
        )

        _ = await harness.repository.recent(limit: 10)

        // Poll until the latest published status is `.readSucceeded`.
        // The earlier append will publish `.writeSucceeded` first; the
        // repository's read call then overwrites it.
        let observer = harness.observer
        try await waitForCondition(description: "recent records .readSucceeded") {
            await MainActor.run { observer.current == .readSucceeded }
        }
    }

    func test_recent_onBadDB_recordsReadFailed() async throws {
        // Failure injection: feed `search(query:)` a raw FTS5 pattern made
        // up of punctuation only. GRDB's `makeFTS5Pattern(rawPattern:
        // forTable:)` throws a `DatabaseError` for such patterns; the
        // error flows through the existing catch in
        // `TranscriptRepository.search(query:)` → `.readFailed`.
        //
        // Per the locked v3 plan: "FTS pattern compile failures inside
        // `database.read { ... }` flow through the existing catch →
        // `.readFailed`. This matches the reframe — FTS compile is just
        // a failed read, not a special case."
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        try await harness.repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "present")
        )

        let results = await harness.repository.search(query: "\"\"\"")

        XCTAssertEqual(results, [], "Malformed FTS5 pattern should yield empty results")
        let observer = harness.observer
        try await waitForCondition(description: "search records .readFailed") {
            await MainActor.run { observer.current == .readFailed }
        }
    }

    // MARK: - Writes

    func test_append_happyPath_recordsWriteSucceeded() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        try await harness.repository.append(
            makeEntry(timestamp: Date(timeIntervalSince1970: 100), text: "first")
        )

        let observer = harness.observer
        try await waitForCondition(description: "append records .writeSucceeded") {
            await MainActor.run { observer.current == .writeSucceeded }
        }
    }

    func test_append_duplicatePKFailure_recordsWriteFailed() async throws {
        // Matches `TranscriptRepositoryTests.test_append_wrapsGRDBFailureInTranscriptStorageError`:
        // insert the same primary key twice; the second append throws
        // `TranscriptStorageError.queryFailed(underlying:)` and records
        // `.writeFailed` before re-throwing.
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        let duplicateID = UUID()
        try await harness.repository.append(
            makeEntry(id: duplicateID, timestamp: Date(timeIntervalSince1970: 100), text: "a")
        )

        do {
            try await harness.repository.append(
                makeEntry(id: duplicateID, timestamp: Date(timeIntervalSince1970: 200), text: "b")
            )
            XCTFail("Expected duplicate-PK insert to throw")
        } catch let error as TranscriptStorageError {
            guard case .queryFailed = error else {
                XCTFail("Expected .queryFailed, got \(error)")
                return
            }
        } catch {
            XCTFail("Expected TranscriptStorageError.queryFailed, got \(error)")
        }

        let observer = harness.observer
        try await waitForCondition(description: "append records .writeFailed") {
            await MainActor.run { observer.current == .writeFailed }
        }
    }

    // MARK: - Non-recording paths

    func test_search_emptyQuery_doesNotRecord() async throws {
        let harness = try makeHarness()
        defer { cleanup(harness.base) }

        // Observer starts at .idle (no prior op). An empty-query search
        // short-circuits before touching SQLite, so the observer MUST
        // remain .idle.
        let observer = harness.observer
        let initial = await MainActor.run { observer.current }
        XCTAssertEqual(initial, .idle)

        _ = await harness.repository.search(query: "")
        _ = await harness.repository.search(query: "   ")

        // Give the main-actor hop a chance to fire in case we're wrong —
        // then assert still .idle.
        try await Task.sleep(for: .milliseconds(50))
        let after = await MainActor.run { observer.current }
        XCTAssertEqual(after, .idle, "Empty/whitespace queries must not record an op")
    }

    // MARK: - Helpers

    private struct Harness {
        let database: AppDatabase
        let repository: TranscriptRepository
        let observer: DatabaseOperationObserver
        let base: URL
    }

    private func makeHarness() throws -> Harness {
        let (recordings, base) = try makeTempRecordingsDir()
        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: base,
            managedDirectoryOverrides: [.recordings: recordings]
        )
        let database = try AppDatabase(locator: locator)
        let observer = DatabaseOperationObserver()
        let repository = TranscriptRepository(
            database: database,
            operationObserver: observer,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )
        return Harness(database: database, repository: repository, observer: observer, base: base)
    }

    private func makeTempRecordingsDir() throws -> (recordings: URL, base: URL) {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("DatabaseOperationStatusTests-\(UUID().uuidString)", isDirectory: true)
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

}
