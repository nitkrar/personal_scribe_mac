import Foundation
import XCTest
@testable import SeshatCore

final class SeshatConfigTests: XCTestCase {
    private static let stateLock = NSLock()

    func testBaseDirectoryUsesTestingOverrideAndModelsNestUnderIt() throws {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        SeshatConfig.testingBaseDirectoryOverride = baseDirectory
        defer {
            SeshatConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            SeshatConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let appSupport = try SeshatConfig.baseDirectory()
        let models = try SeshatConfig.modelsDirectory()

        XCTAssertEqual(
            appSupport,
            baseDirectory
                .appendingPathComponent("Seshat", isDirectory: true)
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
            SeshatConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            SeshatConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let baseDirectory = try SeshatConfig.baseDirectory()

        XCTAssertEqual(baseDirectory, override.standardizedFileURL)
    }

    func testUserDefaultsOverride() throws {
        Self.stateLock.lock()
        defer { Self.stateLock.unlock() }

        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        SeshatConfig.baseDirectoryPathPreference(defaults: .standard).persist(override.path)
        defer {
            SeshatConfig.baseDirectoryPathPreference(defaults: .standard).persist(nil)
            SeshatConfig.testingBaseDirectoryOverride = nil
            unsetenv("SESHAT_BASE_DIR")
        }

        let baseDirectory = try SeshatConfig.baseDirectory()

        XCTAssertEqual(baseDirectory, override.standardizedFileURL)
    }

    func testBaseDirectoryPathPreferenceDropsSeshatPrefix() {
        XCTAssertEqual(
            SeshatConfig.baseDirectoryPathPreference(defaults: .standard).key,
            "BaseDirectoryPath"
        )
    }
}
