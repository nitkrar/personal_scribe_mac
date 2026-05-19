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
    public static let currentMigrationVersion: Int = 2
    public static let migrationVersionKey = "PreferenceMigrationVersion"

    public static func migrate(
        defaults: UserDefaults = .standard,
        domainName: String = AppBrand.bundleIdentifier
    ) {
        let current = defaults.integer(forKey: migrationVersionKey)
        let existingInstall = current > 0 || hasPersistedPreferences(
            defaults: defaults,
            domainName: domainName
        )
        guard current < currentMigrationVersion else { return }

        if current < 1 {
            migrateSeshatOnboardingCompleted(defaults: defaults)
        }
        if current < 2 {
            migrateWhisperAdapterFilter(
                defaults: defaults,
                existingInstall: existingInstall
            )
        }

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

    private static func migrateWhisperAdapterFilter(
        defaults: UserDefaults,
        existingInstall: Bool
    ) {
        guard defaults.object(forKey: WhisperAdapterFilter.userDefaultsKey) == nil else {
            return
        }
        guard existingInstall else { return }
        WhisperAdapterFilter.both.persist(to: defaults)
    }

    private static func hasPersistedPreferences(
        defaults: UserDefaults,
        domainName: String
    ) -> Bool {
        guard let domain = defaults.persistentDomain(forName: domainName) else {
            return false
        }
        return domain.isEmpty == false
    }
}
