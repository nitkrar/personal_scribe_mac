import Foundation
import XCTest
@testable import PersonalScribeCore

final class AppConfigBaseDirectoryTests: XCTestCase {
    private static let stateLock = NSLock()

    func testBaseDirectoryUsesTestingOverrideAndModelsNestUnderIt() throws {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        AppConfig.testingBaseDirectoryOverride = baseDirectory
        defer {
            AppConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            AppConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let appSupport = try AppConfig.baseDirectory()
        let models = try AppConfig.modelsDirectory()

        XCTAssertEqual(
            appSupport,
            baseDirectory
                .appendingPathComponent("personal_scribe", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertEqual(
            models,
            appSupport
                .appendingPathComponent("models", isDirectory: true)
                .standardizedFileURL
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: appSupport.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: models.path))
    }

    func testEnvVarOverridesBase() throws {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        setenv("SESHAT_BASE_DIR", override.path, 1)
        defer {
            AppConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            AppConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let baseDirectory = try AppConfig.baseDirectory()

        XCTAssertEqual(baseDirectory, override.standardizedFileURL)
    }

    func testUserDefaultsOverride() throws {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        AppConfig.baseDirectoryPathPreference(defaults: .standard).persist(override.path)
        defer {
            AppConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            AppConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let baseDirectory = try AppConfig.baseDirectory()

        XCTAssertEqual(baseDirectory, override.standardizedFileURL)
    }

    func testBaseDirectoryPathPreferenceDropsSeshatPrefix() {
        XCTAssertEqual(
            AppConfig.baseDirectoryPathPreference(defaults: .standard).key,
            "BaseDirectoryPath"
        )
    }
}
