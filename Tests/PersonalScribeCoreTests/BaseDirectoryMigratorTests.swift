import Foundation
import XCTest
@testable import PersonalScribeCore

final class BaseDirectoryMigratorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testScheduleMoveRecordsPendingWithoutMovingAnything() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: fixture.sourceBase)

        let scheduled = try fixture.migrator.scheduleMove(to: fixture.destinationBase)

        XCTAssertEqual(scheduled, fixture.destinationBase)
        XCTAssertTrue(fileManager.fileExists(atPath: fixture.sourceBase.appendingPathComponent("models").path))
        XCTAssertEqual(try fixture.currentBase(), fixture.sourceBase)
        XCTAssertEqual(AppConfig.pendingBaseDirectory(defaults: fixture.defaults), fixture.destinationBase)
    }

    func testApplyPendingMoveMovesDataAndModesFileThenSwitches() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: fixture.sourceBase)
        try writeData(count: 29, toManagedSubdirectory: "recordings", named: "clip.wav", under: fixture.sourceBase)
        try Data("{}".utf8).write(to: fixture.sourceBase.appendingPathComponent("workflow-modes.json"))
        _ = try fixture.migrator.scheduleMove(to: fixture.destinationBase)

        try fixture.migrator.applyPendingMoveIfNeeded()

        for item in ["models", "recordings", "workflow-modes.json"] {
            XCTAssertFalse(fileManager.fileExists(atPath: fixture.sourceBase.appendingPathComponent(item).path), item)
            XCTAssertTrue(fileManager.fileExists(atPath: fixture.destinationBase.appendingPathComponent(item).path), item)
        }
        XCTAssertEqual(try fixture.currentBase(), fixture.destinationBase)
        XCTAssertNil(AppConfig.pendingBaseDirectory(defaults: fixture.defaults))
    }

    func testApplyPendingMoveRollsBackAndStaysOnOldLocationOnFailure() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        try writeData(count: 17, toManagedSubdirectory: "models", named: "ggml.bin", under: fixture.sourceBase)
        try writeData(count: 29, toManagedSubdirectory: "recordings", named: "clip.wav", under: fixture.sourceBase)
        _ = try fixture.migrator.scheduleMove(to: fixture.destinationBase)
        let conflicting = fixture.destinationBase.appendingPathComponent("recordings", isDirectory: true)
        try fileManager.createDirectory(at: conflicting, withIntermediateDirectories: true)

        XCTAssertThrowsError(try fixture.migrator.applyPendingMoveIfNeeded()) { error in
            XCTAssertEqual(error as? BaseDirectoryMigrationError, .partialFailure(failedSubdir: "recordings"))
        }

        XCTAssertTrue(fileManager.fileExists(atPath: fixture.sourceBase.appendingPathComponent("models").path))
        XCTAssertFalse(fileManager.fileExists(atPath: fixture.destinationBase.appendingPathComponent("models").path))
        XCTAssertEqual(try fixture.currentBase(), fixture.sourceBase)
        XCTAssertNil(AppConfig.pendingBaseDirectory(defaults: fixture.defaults))
    }

    func testScheduleMoveToCurrentLocationClearsPending() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        _ = try fixture.migrator.scheduleMove(to: fixture.destinationBase)

        let scheduled = try fixture.migrator.scheduleMove(to: fixture.sourceBase)

        XCTAssertNil(scheduled)
        XCTAssertNil(AppConfig.pendingBaseDirectory(defaults: fixture.defaults))
    }

    func testScheduleMoveRejectsNonWritableDestination() throws {
        let fixture = try Fixture()
        defer { fixture.tearDown() }
        let notADirectory = fixture.destinationBase.appendingPathComponent("file", isDirectory: false)
        try Data([0x41]).write(to: notADirectory)

        XCTAssertThrowsError(try fixture.migrator.scheduleMove(to: notADirectory)) { error in
            XCTAssertEqual(error as? BaseDirectoryMigrationError, .destinationNotWritable)
        }
        XCTAssertNil(AppConfig.pendingBaseDirectory(defaults: fixture.defaults))
    }

    private struct Fixture {
        let suiteName = "BaseDirectoryMigratorTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let sourceBase: URL
        let destinationBase: URL
        let migrator: BaseDirectoryMigrator
        let previousTestingOverride = AppConfig.testingBaseDirectoryOverride

        init() throws {
            defaults = UserDefaults(suiteName: suiteName)!
            sourceBase = try Self.makeTemporaryDirectory()
            destinationBase = try Self.makeTemporaryDirectory()
            AppConfig.testingBaseDirectoryOverride = nil
            AppConfig.setBaseDirectoryOverride(sourceBase, defaults: defaults)
            migrator = BaseDirectoryMigrator(
                defaults: defaults,
                environment: [:],
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.app)
            )
        }

        func currentBase() throws -> URL {
            try AppConfig.baseDirectory(defaults: defaults, environment: [:])
        }

        func tearDown() {
            AppConfig.testingBaseDirectoryOverride = previousTestingOverride
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: sourceBase)
            try? FileManager.default.removeItem(at: destinationBase)
        }

        private static func makeTemporaryDirectory() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.standardizedFileURL
        }
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

}
