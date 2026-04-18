import Foundation
import XCTest
@testable import SeshatCore

final class SQLiteTranscriptStoreTests: XCTestCase {
    private struct DirectoryContext {
        let baseDirectory: URL
        let recordingsDirectory: URL
        let databaseURL: URL
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

    private func makeIsolatedRecordingsDirectory() throws -> DirectoryContext {
        let baseDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        Self.configLock.lock()
        SeshatConfig.testingBaseDirectoryOverride = baseDirectory
        defer {
            UserDefaults.standard.removeObject(forKey: "SeshatBaseDirectoryPath")
            SeshatConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
            Self.configLock.unlock()
        }

        let recordingsDirectory = try SeshatConfig.recordingsDirectory()
        let databaseURL = recordingsDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        return DirectoryContext(
            baseDirectory: baseDirectory,
            recordingsDirectory: recordingsDirectory,
            databaseURL: databaseURL
        )
    }

    private func cleanup(_ baseDirectory: URL) {
        try? fileManager.removeItem(at: baseDirectory)
    }

    private func makeEntry(index: Int) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: Date(timeIntervalSince1970: TimeInterval(index * 60)),
            text: "entry-\(index)",
            audioDuration: TimeInterval(index) * 0.25,
            processingDuration: TimeInterval(index) * 0.1
        )
    }
}
