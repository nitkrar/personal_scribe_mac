import Foundation
import XCTest
import PersonalScribeCore

final class TranscriptReaderTests: XCTestCase {
    private struct DirectoryContext {
        let baseDirectory: URL
        let recordingsDirectory: URL
    }

    private static let configLock = NSLock()
    private let fileManager = FileManager.default

    func testFakeTranscriptReaderReturnsScriptedEntries() async {
        let older = makeEntry(index: 1, text: "older transcript")
        let newer = makeEntry(index: 2, text: "searchable moon transcript")
        let reader = ScriptedTranscriptReader(
            recentEntries: [newer],
            searchResultsByQuery: ["moon": [newer]],
            allEntries: [newer, older]
        )

        let recent = await loadRecent(from: reader, limit: 1)
        let search = await reader.search(query: "moon")
        let all = await reader.all()

        XCTAssertEqual(recent, [newer])
        XCTAssertEqual(search, [newer])
        XCTAssertEqual(all, [newer, older])
    }

    func testSQLiteTranscriptReaderCallsThroughToSQLiteTranscriptStore() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let older = makeEntry(index: 1, text: "older transcript")
        let newer = makeEntry(index: 2, text: "searchable moon transcript")

        try await store.append(older)
        try await store.append(newer)

        let reader = SQLiteTranscriptReader(store: store)
        let recent = await reader.recent(limit: 1)
        let search = await reader.search(query: "moon")
        let all = await reader.all()

        XCTAssertEqual(recent, [newer])
        XCTAssertEqual(search, [newer])
        XCTAssertEqual(all, [newer, older])
    }

    private func loadRecent(
        from reader: any TranscriptReading,
        limit: Int
    ) async -> [TranscriptEntry] {
        await reader.recent(limit: limit)
    }

    private func makeIsolatedRecordingsDirectory() throws -> DirectoryContext {
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        Self.configLock.lock()
        AppConfig.testingBaseDirectoryOverride = baseDirectory
        defer {
            AppConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            AppConfig.testingBaseDirectoryOverride = nil
            unsetenv("PERSONAL_SCRIBE_BASE_DIR")
            Self.configLock.unlock()
        }

        let recordingsDirectory = try AppConfig.recordingsDirectory()
        return DirectoryContext(
            baseDirectory: baseDirectory,
            recordingsDirectory: recordingsDirectory
        )
    }

    private func cleanup(_ baseDirectory: URL) {
        try? fileManager.removeItem(at: baseDirectory)
    }

    private func makeEntry(index: Int, text: String) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60)),
            text: text,
            audioDuration: TimeInterval(index) * 2,
            processingDuration: TimeInterval(index) * 0.5
        )
    }
}

private struct ScriptedTranscriptReader: TranscriptReading {
    let recentEntries: [TranscriptEntry]
    let searchResultsByQuery: [String: [TranscriptEntry]]
    let allEntries: [TranscriptEntry]

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
    }

    func search(query: String) async -> [TranscriptEntry] {
        searchResultsByQuery[query, default: []]
    }

    func all() async -> [TranscriptEntry] {
        allEntries
    }
}
