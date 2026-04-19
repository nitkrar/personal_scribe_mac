import Foundation
import XCTest
@testable import SeshatCore

final class SQLiteTranscriptStoreTests: XCTestCase {
    private struct DirectoryContext {
        let baseDirectory: URL
        let recordingsDirectory: URL
        let databaseURL: URL
        let jsonlURL: URL
        let temporaryDatabaseURL: URL
    }

    private final class EventRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var events: [SQLiteTranscriptStore.TestingEvent] = []

        func append(_ event: SQLiteTranscriptStore.TestingEvent) {
            lock.lock()
            events.append(event)
            lock.unlock()
        }

        func snapshot() -> [SQLiteTranscriptStore.TestingEvent] {
            lock.lock()
            defer { lock.unlock() }
            return events
        }
    }

    private static let configLock = NSLock()
    private let fileManager = FileManager.default

    func testAppendAndRecentRoundTripPersistsRowsInSQLite() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let entries = [
            makeEntry(index: 1),
            makeEntry(index: 2),
            makeEntry(index: 3),
        ]

        for entry in entries {
            try await store.append(entry)
        }

        let reloadedStore = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let recent = await reloadedStore.recent(limit: 10)
        let count = await reloadedStore.count()

        XCTAssertEqual(recent, Array(entries.reversed()))
        XCTAssertEqual(count, entries.count)
        XCTAssertTrue(fileManager.fileExists(atPath: context.databaseURL.path))
    }

    func testSearchMatchesExactPrefixPhraseAndDiacritics() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let exactEntry = makeEntry(index: 1, text: "launch sequence complete")
        let prefixEntry = makeEntry(index: 2, text: "prefix searches reward patience")
        let phraseEntry = makeEntry(index: 3, text: "swift package manager")
        let diacriticEntry = makeEntry(index: 4, text: "Café before the storm")
        let distractorEntry = makeEntry(index: 5, text: "unrelated material")

        for entry in [exactEntry, prefixEntry, phraseEntry, diacriticEntry, distractorEntry] {
            try await store.append(entry)
        }

        let exactMatches = try await store.search(query: "launch")
        XCTAssertEqual(exactMatches.map(\.id), [exactEntry.id])

        let prefixMatches = try await store.search(query: "pref*")
        XCTAssertEqual(prefixMatches.map(\.id), [prefixEntry.id])

        let phraseMatches = try await store.search(query: "\"swift package\"")
        XCTAssertEqual(phraseMatches.map(\.id), [phraseEntry.id])

        let diacriticMatches = try await store.search(query: "cafe")
        XCTAssertEqual(diacriticMatches.map(\.id), [diacriticEntry.id])
    }

    func testMigratesExistingJSONLAndSkipsCorruptLinesOnlyOnce() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let firstEntry = makeEntry(index: 1, text: "first migrated row")
        let secondEntry = makeEntry(index: 2, text: "second migrated row")
        try writeJSONLLines(
            [
                try encode(entry: firstEntry),
                "{ malformed json",
                try encode(entry: secondEntry),
            ],
            to: context.jsonlURL
        )

        let recorder = EventRecorder()
        let originalSink = SQLiteTranscriptStore.testingEventSink
        SQLiteTranscriptStore.testingEventSink = { event in
            recorder.append(event)
        }
        defer {
            SQLiteTranscriptStore.testingEventSink = originalSink
        }

        let migratedStore = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let migratedRecent = await migratedStore.recent(limit: 10)
        let migratedCount = await migratedStore.count()
        XCTAssertEqual(migratedRecent, [secondEntry, firstEntry])
        XCTAssertEqual(migratedCount, 2)
        XCTAssertTrue(fileManager.fileExists(atPath: context.databaseURL.path))
        XCTAssertTrue(fileManager.fileExists(atPath: context.jsonlURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: context.temporaryDatabaseURL.path))
        XCTAssertEqual(recorder.snapshot(), [.skippedCorruptJSONLLine("{ malformed json")])

        let laterJSONLEntry = makeEntry(index: 3, text: "should not be reimported")
        try appendJSONLLine(try encode(entry: laterJSONLEntry), to: context.jsonlURL)

        let reopenedStore = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let reopenedRecent = await reopenedStore.recent(limit: 10)
        let reopenedCount = await reopenedStore.count()
        XCTAssertEqual(reopenedRecent, [secondEntry, firstEntry])
        XCTAssertEqual(reopenedCount, 2)
        XCTAssertEqual(recorder.snapshot(), [.skippedCorruptJSONLLine("{ malformed json")])
    }

    func testRuntimeGuardsAndGoldenCorpusSmokeQueries() async throws {
        XCTAssertThrowsError(
            try SQLiteTranscriptStore.validateRuntimeMetadata(
                .init(
                    sqliteVersion: "3.37.9",
                    fts5Enabled: true,
                    ftsTableSQL: "CREATE VIRTUAL TABLE transcripts_fts USING fts5(text, tokenize='unicode61 remove_diacritics 2')"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTranscriptStore.OpenError,
                .unsupportedSQLiteVersion(current: "3.37.9", minimum: "3.38.0")
            )
        }

        XCTAssertThrowsError(
            try SQLiteTranscriptStore.validateRuntimeMetadata(
                .init(
                    sqliteVersion: "3.38.0",
                    fts5Enabled: false,
                    ftsTableSQL: "CREATE VIRTUAL TABLE transcripts_fts USING fts5(text, tokenize='unicode61 remove_diacritics 2')"
                )
            )
        ) { error in
            XCTAssertEqual(error as? SQLiteTranscriptStore.OpenError, .missingFTS5CompileOption)
        }

        XCTAssertThrowsError(
            try SQLiteTranscriptStore.validateRuntimeMetadata(
                .init(
                    sqliteVersion: "3.38.0",
                    fts5Enabled: true,
                    ftsTableSQL: "CREATE VIRTUAL TABLE transcripts_fts USING fts5(text)"
                )
            )
        ) { error in
            XCTAssertEqual(
                error as? SQLiteTranscriptStore.OpenError,
                .invalidFTSTokenizerConfiguration(sql: "CREATE VIRTUAL TABLE transcripts_fts USING fts5(text)")
            )
        }

        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try SQLiteTranscriptStore(recordingsDirectory: context.recordingsDirectory)
        let exactEntry = makeEntry(index: 1, text: "launch window confirmed")
        let prefixEntry = makeEntry(index: 2, text: "prefix matching rewards care")
        let phraseEntry = makeEntry(index: 3, text: "swift package manager")
        let diacriticEntry = makeEntry(index: 4, text: "Café au lait")
        let nonMatchEntry = makeEntry(index: 5, text: "silent background noise")

        for entry in [exactEntry, prefixEntry, phraseEntry, diacriticEntry, nonMatchEntry] {
            try await store.append(entry)
        }

        let exactMatches = try await store.search(query: "launch")
        let prefixMatches = try await store.search(query: "pref*")
        let phraseMatches = try await store.search(query: "\"swift package\"")
        let diacriticMatches = try await store.search(query: "cafe")
        let noMatches = try await store.search(query: "galaxy")

        XCTAssertEqual(exactMatches.map(\.id), [exactEntry.id])
        XCTAssertEqual(prefixMatches.map(\.id), [prefixEntry.id])
        XCTAssertEqual(phraseMatches.map(\.id), [phraseEntry.id])
        XCTAssertEqual(diacriticMatches.map(\.id), [diacriticEntry.id])
        XCTAssertEqual(noMatches, [])
    }

    private func makeIsolatedRecordingsDirectory() throws -> DirectoryContext {
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        Self.configLock.lock()
        SeshatConfig.testingBaseDirectoryOverride = baseDirectory
        defer {
            SeshatConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            SeshatConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
            Self.configLock.unlock()
        }

        let recordingsDirectory = try SeshatConfig.recordingsDirectory()
        let databaseURL = recordingsDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let jsonlURL = recordingsDirectory.appendingPathComponent("transcripts.jsonl", isDirectory: false)
        let temporaryDatabaseURL = databaseURL.appendingPathExtension("tmp")
        return DirectoryContext(
            baseDirectory: baseDirectory,
            recordingsDirectory: recordingsDirectory,
            databaseURL: databaseURL,
            jsonlURL: jsonlURL,
            temporaryDatabaseURL: temporaryDatabaseURL
        )
    }

    private func cleanup(_ baseDirectory: URL) {
        try? fileManager.removeItem(at: baseDirectory)
    }

    private func makeEntry(index: Int, text: String? = nil) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60)),
            text: text ?? "entry-\(index)",
            audioDuration: TimeInterval(index) * 0.25,
            processingDuration: TimeInterval(index) * 0.1
        )
    }

    private func encode(entry: TranscriptEntry) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(entry)
        return String(decoding: data, as: UTF8.self)
    }

    private func writeJSONLLines(_ lines: [String], to url: URL) throws {
        let data = (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
        try data.write(to: url)
    }

    private func appendJSONLLine(_ line: String, to url: URL) throws {
        guard let data = "\(line)\n".data(using: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }

        if fileManager.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    }
}
