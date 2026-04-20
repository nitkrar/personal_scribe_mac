import Foundation
import XCTest
@testable import PersonalScribeCore

final class BaseDirectoryMigratorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testMigrationMovesAllSubdirsAndUpdatesConfig() async throws {
        let (suiteName, defaults) = isolatedDefaults()
        let sourceBase = try makeTemporaryDirectory()
        let destinationBase = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(sourceBase)
            cleanup(destinationBase)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(sourceBase, defaults: defaults)
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: sourceBase)
        try writeData(count: 23, toManagedSubdirectory: "modes", named: "dictation.json", under: sourceBase)
        try writeData(count: 29, toManagedSubdirectory: "recordings", named: "clip.wav", under: sourceBase)

        let migrator = BaseDirectoryMigrator(defaults: defaults, environment: [:])

        let report = try await migrator.migrate(to: destinationBase)

        switch report {
        case .noOp:
            XCTFail("Expected a migration report for a different destination.")
        case .migrated(let movedSubdirs, let totalBytes):
            XCTAssertEqual(movedSubdirs, ["models", "modes", "recordings"])
            XCTAssertGreaterThan(totalBytes, 0)
        }

        XCTAssertFalse(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("models").path))
        XCTAssertFalse(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("modes").path))
        XCTAssertFalse(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("recordings").path))
        XCTAssertTrue(fileManager.fileExists(atPath: destinationBase.appendingPathComponent("models").path))
        XCTAssertTrue(fileManager.fileExists(atPath: destinationBase.appendingPathComponent("modes").path))
        XCTAssertTrue(fileManager.fileExists(atPath: destinationBase.appendingPathComponent("recordings").path))
        XCTAssertEqual(
            try AppConfig.baseDirectory(defaults: defaults, environment: [:]),
            destinationBase.standardizedFileURL
        )
    }

    func testMigrationIsNoOpWhenSourceEqualsDestination() async throws {
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
        try writeData(count: 11, toManagedSubdirectory: "models", named: "marker.bin", under: baseDirectory)

        let migrator = BaseDirectoryMigrator(defaults: defaults, environment: [:])

        let report = try await migrator.migrate(to: baseDirectory)

        XCTAssertEqual(report, .noOp)
        XCTAssertTrue(fileManager.fileExists(atPath: baseDirectory.appendingPathComponent("models").path))
        XCTAssertEqual(
            try AppConfig.baseDirectory(defaults: defaults, environment: [:]),
            baseDirectory.standardizedFileURL
        )
    }

    func testMigrationRollsBackOnMidSequenceFailure() async throws {
        let (suiteName, defaults) = isolatedDefaults()
        let sourceBase = try makeTemporaryDirectory()
        let destinationBase = try makeTemporaryDirectory()
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(sourceBase)
            cleanup(destinationBase)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(sourceBase, defaults: defaults)
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: sourceBase)
        try writeData(count: 23, toManagedSubdirectory: "modes", named: "dictation.json", under: sourceBase)
        try writeData(count: 29, toManagedSubdirectory: "recordings", named: "clip.wav", under: sourceBase)

        let conflictingRecordingsDirectory = destinationBase.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: conflictingRecordingsDirectory, withIntermediateDirectories: true)
        try Data(repeating: 0x7F, count: 5).write(
            to: conflictingRecordingsDirectory.appendingPathComponent("existing.txt", isDirectory: false)
        )

        let migrator = BaseDirectoryMigrator(defaults: defaults, environment: [:])

        do {
            _ = try await migrator.migrate(to: destinationBase)
            XCTFail("Expected rollback after a destination collision.")
        } catch {
            XCTAssertEqual(
                error as? BaseDirectoryMigrationError,
                .partialFailure(failedSubdir: "recordings")
            )
        }

        XCTAssertTrue(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("models").path))
        XCTAssertTrue(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("modes").path))
        XCTAssertTrue(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("recordings").path))
        XCTAssertFalse(fileManager.fileExists(atPath: destinationBase.appendingPathComponent("models").path))
        XCTAssertFalse(fileManager.fileExists(atPath: destinationBase.appendingPathComponent("modes").path))
        XCTAssertTrue(fileManager.fileExists(atPath: conflictingRecordingsDirectory.path))
        XCTAssertEqual(
            try AppConfig.baseDirectory(defaults: defaults, environment: [:]),
            sourceBase.standardizedFileURL
        )
    }

    func testMigrationRejectsNonWritableDestination() async throws {
        let (suiteName, defaults) = isolatedDefaults()
        let sourceBase = try makeTemporaryDirectory()
        let parentDirectory = try makeTemporaryDirectory()
        let destinationFile = parentDirectory.appendingPathComponent("not-a-directory", isDirectory: false)
        defer {
            AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(sourceBase)
            cleanup(parentDirectory)
        }

        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = nil
        defer { AppConfig.testingBaseDirectoryOverride = previousTestingOverride }

        AppConfig.setBaseDirectoryOverride(sourceBase, defaults: defaults)
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: sourceBase)
        try Data(repeating: 0x41, count: 3).write(to: destinationFile)

        let migrator = BaseDirectoryMigrator(defaults: defaults, environment: [:])

        do {
            _ = try await migrator.migrate(to: destinationFile)
            XCTFail("Expected a non-writable destination error.")
        } catch {
            XCTAssertEqual(error as? BaseDirectoryMigrationError, .destinationNotWritable)
        }

        XCTAssertTrue(fileManager.fileExists(atPath: sourceBase.appendingPathComponent("models").path))
        XCTAssertEqual(
            try AppConfig.baseDirectory(defaults: defaults, environment: [:]),
            sourceBase.standardizedFileURL
        )
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "BaseDirectoryMigratorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func writeData(
        count: Int,
        toManagedSubdirectory subdirectory: String,
        named fileName: String,
        under baseDirectory: URL
    ) throws {
        let directory = baseDirectory.appendingPathComponent(subdirectory, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(repeating: 0xAB, count: count).write(
            to: directory.appendingPathComponent(fileName, isDirectory: false)
        )
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
