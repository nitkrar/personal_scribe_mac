import Foundation
import XCTest
@testable import SeshatCore

final class TranscriptStoreTests: XCTestCase {
    private struct DirectoryContext {
        let baseDirectory: URL
        let recordingsDirectory: URL
        let fileURL: URL
    }

    private static let configLock = NSLock()
    private let fileManager = FileManager.default

    func testAppendAndRecentRoundTrip() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)
        let entries = [
            makeEntry(index: 1),
            makeEntry(index: 2),
            makeEntry(index: 3),
        ]

        for entry in entries {
            try await store.append(entry)
        }

        let recent = await store.recent(limit: 10)
        let count = await store.count()

        XCTAssertEqual(recent, Array(entries.reversed()))
        XCTAssertEqual(count, entries.count)
        XCTAssertEqual(try readPersistedEntries(from: context.fileURL), entries)
    }

    func testRingEvictsOldestBeyondCapacity() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory, ringCapacity: 3)
        let entries = (1...5).map(makeEntry(index:))

        for entry in entries {
            try await store.append(entry)
        }

        let recent = await store.recent(limit: 10)
        let count = await store.count()

        XCTAssertEqual(recent, Array(entries.suffix(3).reversed()))
        XCTAssertEqual(count, 3)
        XCTAssertEqual(try readPersistedEntries(from: context.fileURL), entries)
    }

    func testPersistenceSurvivesReinit() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let entries = [
            makeEntry(index: 10),
            makeEntry(index: 11),
        ]

        let firstStore = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)
        for entry in entries {
            try await firstStore.append(entry)
        }

        let secondStore = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)
        let recent = await secondStore.recent(limit: 10)
        let count = await secondStore.count()

        XCTAssertEqual(recent, Array(entries.reversed()))
        XCTAssertEqual(count, entries.count)
    }

    func testCorruptLineIsSkippedOnLoad() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let entries = [
            makeEntry(index: 20),
            makeEntry(index: 21),
        ]
        let encoder = makeEncoder()
        let goodLines = try entries.map { entry in
            let data = try encoder.encode(entry)
            return String(decoding: data, as: UTF8.self)
        }
        let contents = ([
            goodLines[0],
            "{ malformed json",
            goodLines[1],
        ].joined(separator: "\n") + "\n").data(using: .utf8)!

        try contents.write(to: context.fileURL)

        let store = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)
        let recent = await store.recent(limit: 10)
        let count = await store.count()

        XCTAssertEqual(recent, Array(entries.reversed()))
        XCTAssertEqual(count, entries.count)
    }

    func testNewFileIsCreatedWith0600Permissions() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        _ = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)

        let attrs = try fileManager.attributesOfItem(atPath: context.fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testExistingFileIsMigratedTo0600Permissions() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        try fileManager.createDirectory(
            at: context.recordingsDirectory,
            withIntermediateDirectories: true
        )
        XCTAssertTrue(fileManager.createFile(
            atPath: context.fileURL.path,
            contents: nil,
            attributes: [.posixPermissions: NSNumber(value: 0o644)]
        ))

        _ = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)

        let attrs = try fileManager.attributesOfItem(atPath: context.fileURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(perms, 0o600)
    }

    func testRecentLimitCaps() async throws {
        let context = try makeIsolatedRecordingsDirectory()
        defer { cleanup(context.baseDirectory) }

        let store = try TranscriptStoreJSONL(recordingsDirectory: context.recordingsDirectory)
        let entries = (1...10).map(makeEntry(index:))

        for entry in entries {
            try await store.append(entry)
        }

        let recent = await store.recent(limit: 3)
        let count = await store.count()

        XCTAssertEqual(recent, Array(entries.suffix(3).reversed()))
        XCTAssertEqual(count, entries.count)
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
        let fileURL = recordingsDirectory.appendingPathComponent("transcripts.jsonl", isDirectory: false)
        return DirectoryContext(
            baseDirectory: baseDirectory,
            recordingsDirectory: recordingsDirectory,
            fileURL: fileURL
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

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private func readPersistedEntries(from fileURL: URL) throws -> [TranscriptEntry] {
        let data = try Data(contentsOf: fileURL)
        let decoder = makeDecoder()
        return try data
            .split(separator: 0x0A, omittingEmptySubsequences: true)
            .map { lineData in
                try decoder.decode(TranscriptEntry.self, from: Data(lineData))
            }
    }
}
