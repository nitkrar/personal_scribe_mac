import Foundation

/// One-shot idempotent `UserDefaults` migration for the Seshat → PersonalScribe /
/// Ninimma rename. Each migration version is a cumulative step: new versions
/// bump `currentMigrationVersion` and add a handler here. Already-migrated
/// installs no-op.
///
/// - Version 1: strips the `Seshat` prefix from persisted defaults keys.
///   Currently scopes to `SeshatOnboardingCompleted → OnboardingCompleted`
///   (the only branded key on trunk at rename time). UserDefaults keys are
///   bundle-scoped by the `com.nitkrar.personal_scribe` domain, so the rename
///   policy is "strip the prefix" rather than swap to `PersonalScribe*`.
public enum PreferenceMigrator {
    public static let currentMigrationVersion: Int = 1
    public static let migrationVersionKey = "PreferenceMigrationVersion"

    public static func migrate(defaults: UserDefaults = .standard) {
        let current = defaults.integer(forKey: migrationVersionKey)
        guard current < currentMigrationVersion else { return }

        migrateSeshatOnboardingCompleted(defaults: defaults)

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    private static func migrateSeshatOnboardingCompleted(defaults: UserDefaults) {
        let oldKey = "SeshatOnboardingCompleted"
        let newKey = "OnboardingCompleted"
        guard let oldValue = defaults.object(forKey: oldKey) else { return }
        if defaults.object(forKey: newKey) == nil {
            defaults.set(oldValue, forKey: newKey)
        }
        defaults.removeObject(forKey: oldKey)
    }
}
