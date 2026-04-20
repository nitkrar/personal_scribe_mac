import Foundation
import XCTest
@testable import PersonalScribeCore

final class StorageLocatorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testManagedDirectoryCasesMatchLockedContract() {
        XCTAssertEqual(
            ManagedDirectory.allCases.map(\.pathComponent),
            ["models", "modes", "recordings", "logs", "cache"]
        )
    }

    func testBaseDirectoryUsesTestingOverrideBeforeEnvironmentAndUserDefaults() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let testingOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let envOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaultsOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults.set(defaultsOverride.path, forKey: AppConfig.baseDirectoryUserDefaultsKey)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(testingOverride)
            cleanup(envOverride)
            cleanup(defaultsOverride)
        }

        let locator = AppStorageLocator(
            defaults: defaults,
            environment: [AppConfig.baseDirectoryEnvironmentVariableName: envOverride.path],
            testingBaseDirectoryOverrideProvider: { testingOverride }
        )

        XCTAssertEqual(
            locator.baseDirectory,
            testingOverride
                .appendingPathComponent("personal_scribe", isDirectory: true)
                .standardizedFileURL
        )
    }

    func testBaseDirectoryUsesEnvironmentBeforeUserDefaults() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let envOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let defaultsOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults.set(defaultsOverride.path, forKey: AppConfig.baseDirectoryUserDefaultsKey)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(envOverride)
            cleanup(defaultsOverride)
        }

        let locator = AppStorageLocator(
            defaults: defaults,
            environment: [AppConfig.baseDirectoryEnvironmentVariableName: envOverride.path],
            testingBaseDirectoryOverrideProvider: { nil }
        )

        XCTAssertEqual(locator.baseDirectory, envOverride.standardizedFileURL)
    }

    func testBaseDirectoryUsesUserDefaultsWhenEnvironmentIsMissing() throws {
        let (suiteName, defaults) = isolatedDefaults()
        let defaultsOverride = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defaults.set(defaultsOverride.path, forKey: AppConfig.baseDirectoryUserDefaultsKey)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
            cleanup(defaultsOverride)
        }

        let locator = AppStorageLocator(
            defaults: defaults,
            environment: [:],
            testingBaseDirectoryOverrideProvider: { nil }
        )

        XCTAssertEqual(locator.baseDirectory, defaultsOverride.standardizedFileURL)
    }

    func testBaseDirectoryFallsBackToApplicationSupportSeshat() {
        let (suiteName, defaults) = isolatedDefaults()
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let locator = AppStorageLocator(
            fileManager: fileManager,
            defaults: defaults,
            environment: [:],
            testingBaseDirectoryOverrideProvider: { nil }
        )

        let expected = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("personal_scribe", isDirectory: true)
            .standardizedFileURL

        XCTAssertEqual(locator.baseDirectory, expected)
    }

    func testBaseDirectoryIsPureResolutionAndEnsureDirectoriesExistCreatesAllManagedRootsIdempotently() throws {
        let temporaryRoot = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            cleanup(temporaryRoot)
        }

        let locator = AppStorageLocator(
            defaults: .standard,
            environment: [:],
            testingBaseDirectoryOverrideProvider: { temporaryRoot }
        )

        let resolvedBaseDirectory = locator.baseDirectory
        XCTAssertFalse(fileManager.fileExists(atPath: resolvedBaseDirectory.path))

        try locator.ensureDirectoriesExist()
        try locator.ensureDirectoriesExist()

        XCTAssertTrue(fileManager.fileExists(atPath: resolvedBaseDirectory.path))
        for directory in ManagedDirectory.allCases {
            let directoryURL = locator.url(for: directory)
            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory)
            XCTAssertTrue(exists, "Expected \(directory.pathComponent) to exist.")
            XCTAssertTrue(isDirectory.boolValue, "Expected \(directory.pathComponent) to be a directory.")
        }
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "StorageLocatorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
