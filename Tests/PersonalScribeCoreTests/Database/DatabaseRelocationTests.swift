import Foundation
import XCTest
@testable import PersonalScribeCore

final class DatabaseRelocationTests: XCTestCase {
    private let fileManager = FileManager.default

    func testRelocateMovesSqliteAndSidecars() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(baseDirectory)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(baseDirectory, defaults: defaults)

        let sourceDirectory = baseDirectory.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sqliteURL = sourceDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let walURL = sourceDirectory.appendingPathComponent("transcripts.sqlite-wal", isDirectory: false)
        let shmURL = sourceDirectory.appendingPathComponent("transcripts.sqlite-shm", isDirectory: false)
        try writeMarker(Data("sqlite".utf8), to: sqliteURL)
        try writeMarker(Data("wal".utf8), to: walURL)
        try writeMarker(Data("shm".utf8), to: shmURL)

        let migrator = makeMigrator(defaults: defaults)

        try migrator.relocateLegacyDatabaseIfNeeded()

        let destinationDirectory = baseDirectory.appendingPathComponent("db", isDirectory: true)
        XCTAssertEqual(
            try Data(contentsOf: destinationDirectory.appendingPathComponent("transcripts.sqlite")),
            Data("sqlite".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDirectory.appendingPathComponent("transcripts.sqlite-wal")),
            Data("wal".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDirectory.appendingPathComponent("transcripts.sqlite-shm")),
            Data("shm".utf8)
        )
        XCTAssertFalse(fileManager.fileExists(atPath: sqliteURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: walURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: shmURL.path))
    }

    func testRelocateIsNoOpWhenDestinationExists() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(baseDirectory)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(baseDirectory, defaults: defaults)

        let sourceDirectory = baseDirectory.appendingPathComponent("recordings", isDirectory: true)
        let destinationDirectory = baseDirectory.appendingPathComponent("db", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let sourceURL = sourceDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let destinationURL = destinationDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        try writeMarker(Data("source".utf8), to: sourceURL)
        try writeMarker(Data("destination".utf8), to: destinationURL)

        let migrator = makeMigrator(defaults: defaults)

        try migrator.relocateLegacyDatabaseIfNeeded()

        XCTAssertEqual(try Data(contentsOf: sourceURL), Data("source".utf8))
        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("destination".utf8))
    }

    func testRelocateIsNoOpWhenSourceMissing() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(baseDirectory)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(baseDirectory, defaults: defaults)

        let migrator = makeMigrator(defaults: defaults)

        XCTAssertNoThrow(try migrator.relocateLegacyDatabaseIfNeeded())
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: baseDirectory.appendingPathComponent("db/transcripts.sqlite").path
            )
        )
    }

    func testRelocateMovesOnlySidecarsPresent() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let baseDirectory = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(baseDirectory)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(baseDirectory, defaults: defaults)

        let sourceDirectory = baseDirectory.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
        let sqliteURL = sourceDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let walURL = sourceDirectory.appendingPathComponent("transcripts.sqlite-wal", isDirectory: false)
        try writeMarker(Data("sqlite".utf8), to: sqliteURL)
        try writeMarker(Data("wal".utf8), to: walURL)

        let migrator = makeMigrator(defaults: defaults)

        try migrator.relocateLegacyDatabaseIfNeeded()

        let destinationDirectory = baseDirectory.appendingPathComponent("db", isDirectory: true)
        XCTAssertEqual(
            try Data(contentsOf: destinationDirectory.appendingPathComponent("transcripts.sqlite")),
            Data("sqlite".utf8)
        )
        XCTAssertEqual(
            try Data(contentsOf: destinationDirectory.appendingPathComponent("transcripts.sqlite-wal")),
            Data("wal".utf8)
        )
        XCTAssertFalse(
            fileManager.fileExists(
                atPath: destinationDirectory.appendingPathComponent("transcripts.sqlite-shm").path
            )
        )
        XCTAssertFalse(fileManager.fileExists(atPath: sqliteURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: walURL.path))
    }

    private func makeMigrator(defaults: UserDefaults) -> BaseDirectoryMigrator {
        BaseDirectoryMigrator(
            defaults: defaults,
            environment: [:],
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
        )
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "DatabaseRelocationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func writeMarker(_ data: Data, to url: URL) throws {
        try data.write(to: url)
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
