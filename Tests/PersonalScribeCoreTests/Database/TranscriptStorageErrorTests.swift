import Foundation
import XCTest
@testable import PersonalScribeCore

/// Planting-a-corrupt-file test: verifies that `AppDatabase.init` surfaces
/// failures as `TranscriptStorageError`, not a raw GRDB error. The exact
/// variant (`openFailed` vs `migrationFailed` vs a `runtimeUnsupported` /
/// `queryFailed` leak) is implementation-dependent on how GRDB surfaces
/// "file is not a database" — plan §3 locks only the envelope type.
final class TranscriptStorageErrorTests: XCTestCase {
    private let fileManager = FileManager.default

    func test_init_onMalformedNonSQLiteFile_throwsTranscriptStorageError() throws {
        let baseDir = try makeTempBaseDir()
        defer { cleanup(baseDir) }

        let databaseDirectory = baseDir.appendingPathComponent("db", isDirectory: true)
        try fileManager.createDirectory(at: databaseDirectory, withIntermediateDirectories: true)
        let databaseURL = databaseDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)

        // Plant 64 bytes of random non-SQLite content at the target path BEFORE
        // init. The SQLite header magic is "SQLite format 3\0" — overwriting
        // with filler guarantees GRDB rejects it when it first opens.
        let garbage = Data(repeating: 0xAB, count: 64)
        try garbage.write(to: databaseURL)

        let locator = FixedBaseDirectoryStorageLocator(baseDirectory: baseDir)

        do {
            _ = try AppDatabase(locator: locator)
            XCTFail("Init must reject a malformed, non-SQLite file at the target path")
        } catch is TranscriptStorageError {
            // Success: any variant of the domain error is acceptable here —
            // the contract is the envelope, not the specific case.
        } catch {
            XCTFail(
                "Expected TranscriptStorageError, got \(type(of: error)): \(error)"
            )
        }
    }

    // MARK: - Helpers

    private func makeTempBaseDir() throws -> URL {
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("TranscriptStorageErrorTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func cleanup(_ base: URL) {
        try? fileManager.removeItem(at: base)
    }
}
