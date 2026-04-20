import Foundation
import XCTest
@testable import PersonalScribeCore

final class PreferenceMigratorTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.PreferenceMigrator.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func testMigratesLegacyKeyValue() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults)

        XCTAssertEqual(defaults.object(forKey: "OnboardingCompleted") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testSkipsWhenMigrationAlreadyRun() {
        let defaults = isolatedDefaults()
        defaults.set(PreferenceMigrator.currentMigrationVersion, forKey: PreferenceMigrator.migrationVersionKey)
        defaults.set(true, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults)

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
        let defaults = isolatedDefaults()

        PreferenceMigrator.migrate(defaults: defaults)

        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertNil(defaults.object(forKey: "OnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }

    func testPreservesExistingNewKeyValue() {
        let defaults = isolatedDefaults()
        defaults.set(true, forKey: "OnboardingCompleted")
        defaults.set(false, forKey: "SeshatOnboardingCompleted")

        PreferenceMigrator.migrate(defaults: defaults)

        // Existing new-key value wins over the legacy value; legacy key is
        // still cleaned up so future launches have no stale data.
        XCTAssertEqual(defaults.object(forKey: "OnboardingCompleted") as? Bool, true)
        XCTAssertNil(defaults.object(forKey: "SeshatOnboardingCompleted"))
        XCTAssertEqual(
            defaults.integer(forKey: PreferenceMigrator.migrationVersionKey),
            PreferenceMigrator.currentMigrationVersion
        )
    }
}
