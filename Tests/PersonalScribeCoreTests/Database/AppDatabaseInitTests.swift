import Foundation
import XCTest
@testable import PersonalScribeCore

/// Init-surface tests for `AppDatabase` (plan §3 Pass 1 scope): empty-dir
/// creation and idempotent reopen. Does not cover cross-type contract tests
/// (those belong on `TranscriptRepository` in step 1.3).
final class AppDatabaseInitTests: XCTestCase {
    private let fileManager = FileManager.default

    func test_init_onEmptyDirectory_createsSQLiteFile() throws {
        let baseDir = try makeTempBaseDir()
        defer { cleanup(baseDir) }

        let locator = FixedBaseDirectoryStorageLocator(baseDirectory: baseDir)

        let databaseURL = baseDir.appendingPathComponent("db/transcripts.sqlite", isDirectory: false)
        XCTAssertFalse(
            fileManager.fileExists(atPath: databaseURL.path),
            "precondition: SQLite file must not exist before init"
        )

        _ = try AppDatabase(locator: locator)

        XCTAssertTrue(
            fileManager.fileExists(atPath: databaseURL.path),
            "init must create the SQLite file at the locator-derived path"
        )
    }

    func test_init_reopeningExistingFile_isIdempotent() throws {
        let baseDir = try makeTempBaseDir()
        defer { cleanup(baseDir) }

        let locator = FixedBaseDirectoryStorageLocator(baseDirectory: baseDir)

        _ = try AppDatabase(locator: locator)

        XCTAssertNoThrow(
            _ = try AppDatabase(locator: locator),
            "reopening an existing, migrated SQLite file must not throw"
        )
    }

    // MARK: - Helpers

    private func makeTempBaseDir() throws -> URL {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("AppDatabaseInitTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ base: URL) {
        try? fileManager.removeItem(at: base)
    }
}
