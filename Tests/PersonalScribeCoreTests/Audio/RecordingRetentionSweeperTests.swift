import Foundation
import XCTest
@testable import PersonalScribeCore

final class RecordingRetentionSweeperTests: XCTestCase {
    private let fileManager = FileManager.default

    func testSweepSkipsWhenRetentionIsNever() async throws {
        let recordingsDirectory = try makeTemporaryDirectory()
        defer { cleanup(recordingsDirectory) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldFile = recordingsDirectory.appendingPathComponent("old.wav", isDirectory: false)
        try Data("old".utf8).write(to: oldFile)
        try setModificationDate(now.addingTimeInterval(-8 * 86_400), for: oldFile)
        let repository = RecordingRetentionRepositorySpy()
        let sweeper = RecordingRetentionSweeper(
            recordingsDirectory: { recordingsDirectory },
            repository: repository,
            retentionDays: { 0 },
            now: { now },
            diagnostics: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        await sweeper.sweep()

        XCTAssertTrue(fileManager.fileExists(atPath: oldFile.path))
        let calls = await repository.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testSweepDeletesFilesOlderThanCutoff() async throws {
        let recordingsDirectory = try makeTemporaryDirectory()
        defer { cleanup(recordingsDirectory) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldFile = recordingsDirectory.appendingPathComponent("old.wav", isDirectory: false)
        let recentFile = recordingsDirectory.appendingPathComponent("recent.wav", isDirectory: false)
        try Data("old".utf8).write(to: oldFile)
        try Data("recent".utf8).write(to: recentFile)
        try setModificationDate(now.addingTimeInterval(-8 * 86_400), for: oldFile)
        try setModificationDate(now.addingTimeInterval(-2 * 86_400), for: recentFile)
        let repository = RecordingRetentionRepositorySpy()
        let sweeper = RecordingRetentionSweeper(
            recordingsDirectory: { recordingsDirectory },
            repository: repository,
            retentionDays: { 7 },
            now: { now },
            diagnostics: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        await sweeper.sweep()

        XCTAssertFalse(fileManager.fileExists(atPath: oldFile.path))
        XCTAssertTrue(fileManager.fileExists(atPath: recentFile.path))
    }

    func testSweepKeepsRecentFiles() async throws {
        let recordingsDirectory = try makeTemporaryDirectory()
        defer { cleanup(recordingsDirectory) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let recentFile = recordingsDirectory.appendingPathComponent("recent.wav", isDirectory: false)
        try Data("recent".utf8).write(to: recentFile)
        try setModificationDate(now.addingTimeInterval(-12 * 3_600), for: recentFile)
        let repository = RecordingRetentionRepositorySpy()
        let sweeper = RecordingRetentionSweeper(
            recordingsDirectory: { recordingsDirectory },
            repository: repository,
            retentionDays: { 7 },
            now: { now },
            diagnostics: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        await sweeper.sweep()

        XCTAssertTrue(fileManager.fileExists(atPath: recentFile.path))
        let calls = await repository.calls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testSweepNullifiesAudioFilenameColumns() async throws {
        let recordingsDirectory = try makeTemporaryDirectory()
        defer { cleanup(recordingsDirectory) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = recordingsDirectory.appendingPathComponent("first.wav", isDirectory: false)
        let second = recordingsDirectory.appendingPathComponent("second.wav", isDirectory: false)
        try Data("first".utf8).write(to: first)
        try Data("second".utf8).write(to: second)
        try setModificationDate(now.addingTimeInterval(-9 * 86_400), for: first)
        try setModificationDate(now.addingTimeInterval(-8 * 86_400), for: second)
        let repository = RecordingRetentionRepositorySpy()
        let sweeper = RecordingRetentionSweeper(
            recordingsDirectory: { recordingsDirectory },
            repository: repository,
            retentionDays: { 7 },
            now: { now },
            diagnostics: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        await sweeper.sweep()

        let calls = await repository.calls()
        XCTAssertEqual(calls, [["first.wav", "second.wav"]])
    }

    func testSweepIsIdempotentWithinSamePeriod() async throws {
        let recordingsDirectory = try makeTemporaryDirectory()
        defer { cleanup(recordingsDirectory) }

        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let oldFile = recordingsDirectory.appendingPathComponent("old.wav", isDirectory: false)
        try Data("old".utf8).write(to: oldFile)
        try setModificationDate(now.addingTimeInterval(-8 * 86_400), for: oldFile)
        let repository = RecordingRetentionRepositorySpy()
        let sweeper = RecordingRetentionSweeper(
            recordingsDirectory: { recordingsDirectory },
            repository: repository,
            retentionDays: { 7 },
            now: { now },
            diagnostics: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )

        await sweeper.sweep()
        await sweeper.sweep()

        XCTAssertFalse(fileManager.fileExists(atPath: oldFile.path))
        let calls = await repository.calls()
        XCTAssertEqual(calls, [["old.wav"]])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("RecordingRetentionSweeperTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.standardizedFileURL
    }

    private func setModificationDate(_ date: Date, for url: URL) throws {
        try fileManager.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}

private actor RecordingRetentionRepositorySpy: TranscriptAudioFilenameNullifying {
    private var capturedCalls: [[String]] = []

    func nullifyAudioFilenames(_ filenames: [String]) async throws {
        capturedCalls.append(filenames.sorted())
    }

    func calls() -> [[String]] {
        capturedCalls
    }
}
