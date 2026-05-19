import Foundation
import XCTest
@testable import PersonalScribeCore

final class PreferenceMigratorTests: XCTestCase {
    private func isolatedDefaults() -> (defaults: UserDefaults, domainName: String) {
        let suiteName = "PersonalScribeTests.PreferenceMigrator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return (defaults, suiteName)
    }

    func testMigratesLegacyKeyValue() {
        let (defaults, domainName) = isolatedDefaults()
        defaults.set(true, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        XCTAssertEqual(defaults.object(forKey: "OnboardingCompleted") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testSkipsWhenMigrationAlreadyRun() {
        let (defaults, domainName) = isolatedDefaults()
        defaults.set(PreferenceMigrator.currentMigrationVersion, forKey: PreferenceMigrator.migrationVersionKey)
        defaults.set(true, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        // Already-migrated run must NOT touch the legacy key; leaves any stray
        // value in place (since the one-shot handler never runs).
        XCTAssertEqual(defaults.object(forKey: "SeshatOnboardingCompleted") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "OnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testNoOpWhenLegacyKeyAbsent() {
        let (defaults, domainName) = isolatedDefaults()

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertNil(defaults.object(forKey: "OnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testPreservesExistingNewKeyValue() {
        let (defaults, domainName) = isolatedDefaults()
        defaults.set(true, forKey: "OnboardingCompleted")
        defaults.set(false, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        // Existing new-key value wins over the legacy value; legacy key is
        // still cleaned up so future launches have no stale data.
        XCTAssertEqual(defaults.object(forKey: "OnboardingCompleted") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testFreshInstallLeavesWhisperAdapterFilterUnsetSoDefaultResolvesToNative() {
        let (defaults, domainName) = isolatedDefaults()

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .native)
        XCTAssertNil(defaults.object(forKey: WhisperAdapterFilter.userDefaultsKey))
    }

    func testExistingInstallMigratesWhisperAdapterFilterToBoth() {
        let (defaults, domainName) = isolatedDefaults()
        defaults.set(true, forKey: "OnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .both)
    }

    func testExistingWhisperAdapterFilterValueWinsDuringMigration() {
        let (defaults, domainName) = isolatedDefaults()
        defaults.set(1, forKey: PreferenceMigrator.migrationVersionKey)
        WhisperAdapterFilter.bridge.persist(to: defaults)

        PreferenceMigrator.migrate(defaults: defaults, domainName: domainName)

        XCTAssertEqual(WhisperAdapterFilter.resolve(from: defaults), .bridge)
    }
}
