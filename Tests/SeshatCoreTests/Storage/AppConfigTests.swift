import Foundation
import XCTest
@testable import SeshatCore

final class AppConfigTests: XCTestCase {
    private static let stateLock = NSLock()

    func testConstantsAndOverrideNamesMatchLegacyContract() {
        XCTAssertEqual(AppConfig.sampleRate, 16_000)
        XCTAssertEqual(AppConfig.channelCount, 1)
        XCTAssertEqual(AppConfig.modelId, ModelRegistry.defaultModelId)
        XCTAssertEqual(AppConfig.baseDirectoryUserDefaultsKey, "SeshatBaseDirectoryPath")
        XCTAssertEqual(AppConfig.baseDirectoryEnvironmentVariableName, "SESHAT_BASE_DIR")
    }

    func testSetBaseDirectoryOverrideWritesAndClearsLegacyDefaultsKey() {
        let (suiteName, defaults) = isolatedDefaults()
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        AppConfig.setBaseDirectoryOverride(override, defaults: defaults)
        XCTAssertEqual(
            defaults.string(forKey: AppConfig.baseDirectoryUserDefaultsKey),
            override.standardizedFileURL.path
        )

        AppConfig.setBaseDirectoryOverride(nil, defaults: defaults)
        XCTAssertNil(defaults.object(forKey: AppConfig.baseDirectoryUserDefaultsKey))
    }

    func testLiveStorageLocatorUsesCanonicalTestingOverrideState() {
        Self.stateLock.lock()
        defer {
            Self.stateLock.unlock()
        }

        let (suiteName, defaults) = isolatedDefaults()
        let override = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let previousOverride = AppConfig.testingBaseDirectoryOverride
        AppConfig.testingBaseDirectoryOverride = override
        defer {
            AppConfig.testingBaseDirectoryOverride = previousOverride
            defaults.removePersistentDomain(forName: suiteName)
        }

        let locator = AppConfig.liveStorageLocator(defaults: defaults, environment: [:])

        XCTAssertEqual(
            locator.baseDirectory,
            override
                .appendingPathComponent("Seshat", isDirectory: true)
                .standardizedFileURL
        )
    }

    private func isolatedDefaults() -> (suiteName: String, defaults: UserDefaults) {
        let suiteName = "AppConfigTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return (suiteName, defaults)
    }
}
