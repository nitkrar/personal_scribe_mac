import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class LegacyToggleMigratorTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "LegacyToggleMigratorTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - Snapshot

    func testSnapshotDefaultsAreVadOnAndPasteOn() {
        // No keys set → both fall back to legacy defaults (true, true).
        let snapshot = LegacyToggleSnapshot.read(from: defaults)
        XCTAssertTrue(snapshot.vadAutoStopEnabled)
        XCTAssertTrue(snapshot.autoPasteEnabled)
    }

    func testSnapshotReflectsExplicitlyStoredValues() {
        defaults.set(false, forKey: "VadAutoStopEnabled")
        defaults.set(false, forKey: "AutoPasteEnabled")
        let snapshot = LegacyToggleSnapshot.read(from: defaults)
        XCTAssertFalse(snapshot.vadAutoStopEnabled)
        XCTAssertFalse(snapshot.autoPasteEnabled)
    }

    func testDiffersFromBuiltInWhenVadOnOrPasteOff() {
        // Built-in: VAD off, paste on. Anything else → differs.
        XCTAssertTrue(
            LegacyToggleSnapshot(vadAutoStopEnabled: true, autoPasteEnabled: true)
                .differsFromBuiltInDictation
        )
        XCTAssertTrue(
            LegacyToggleSnapshot(vadAutoStopEnabled: false, autoPasteEnabled: false)
                .differsFromBuiltInDictation
        )
        XCTAssertFalse(
            LegacyToggleSnapshot(vadAutoStopEnabled: false, autoPasteEnabled: true)
                .differsFromBuiltInDictation
        )
    }

    // MARK: - runIfNeeded

    func testFreshDefaultsForkToMigratedDictationWithVadAndPaste() throws {
        // Default legacy state: VAD on, paste on → built-in differs (no
        // VAD), so a fork is needed.
        let registry = try makeRegistry()
        let migrator = LegacyToggleMigrator(registry: registry, defaults: defaults)

        try migrator.runIfNeeded()

        XCTAssertEqual(registry.activeMode.id, "dictation-migrated")
        XCTAssertEqual(registry.activeMode.name, "Dictation (migrated)")

        let captureKinds = registry.activeMode.captureControllers.map(captureKind(of:))
        XCTAssertEqual(captureKinds, ["vad", "manualHotkey"])

        let outputKinds = registry.activeMode.outputSinks.map(outputKind(of:))
        XCTAssertEqual(outputKinds, ["clipboard", "frontmostPaste", "transcriptHistorySQLite"])
    }

    func testVadOffPasteOnMatchesBuiltInAndSkipsFork() throws {
        defaults.set(false, forKey: "VadAutoStopEnabled")
        defaults.set(true, forKey: "AutoPasteEnabled")

        let registry = try makeRegistry()
        let migrator = LegacyToggleMigrator(registry: registry, defaults: defaults)

        try migrator.runIfNeeded()

        XCTAssertEqual(registry.activeMode.id, "dictation")
        XCTAssertEqual(registry.allModes.map(\.id), ["dictation"])
        XCTAssertTrue(defaults.bool(forKey: LegacyToggleMigrator.migrationFlagKey))
    }

    func testVadOffPasteOffForksWithoutVadWithoutPaste() throws {
        defaults.set(false, forKey: "VadAutoStopEnabled")
        defaults.set(false, forKey: "AutoPasteEnabled")

        let registry = try makeRegistry()
        let migrator = LegacyToggleMigrator(registry: registry, defaults: defaults)

        try migrator.runIfNeeded()

        XCTAssertEqual(registry.activeMode.id, "dictation-migrated")
        let captureKinds = registry.activeMode.captureControllers.map(captureKind(of:))
        XCTAssertEqual(captureKinds, ["manualHotkey"])
        let outputKinds = registry.activeMode.outputSinks.map(outputKind(of:))
        XCTAssertEqual(outputKinds, ["clipboard", "transcriptHistorySQLite"])
    }

    func testRunIfNeededIsIdempotent() throws {
        let registry = try makeRegistry()
        let migrator = LegacyToggleMigrator(registry: registry, defaults: defaults)

        try migrator.runIfNeeded()
        let modesAfterFirst = registry.allModes.map(\.id)

        // Re-run should be a no-op.
        try migrator.runIfNeeded()
        XCTAssertEqual(registry.allModes.map(\.id), modesAfterFirst)
    }

    func testAlreadyMigratedFlagSkipsFork() throws {
        // Pre-set the flag → migration must not run even if state would
        // otherwise warrant it.
        defaults.set(true, forKey: LegacyToggleMigrator.migrationFlagKey)
        defaults.set(true, forKey: "VadAutoStopEnabled") // would normally fork

        let registry = try makeRegistry()
        let migrator = LegacyToggleMigrator(registry: registry, defaults: defaults)

        try migrator.runIfNeeded()

        XCTAssertEqual(registry.allModes.map(\.id), ["dictation"])
        XCTAssertEqual(registry.activeMode.id, "dictation")
    }

    // MARK: - Helpers

    private func makeRegistry() throws -> WorkflowModeRegistry {
        let store = InMemoryWorkflowModeStore()
        return try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
    }

    private func captureKind(of spec: CaptureControllerSpec) -> String {
        switch spec {
        case .vad: return "vad"
        case .manualHotkey: return "manualHotkey"
        }
    }

    private func outputKind(of spec: OutputSinkSpec) -> String {
        switch spec {
        case .clipboard: return "clipboard"
        case .frontmostPaste: return "frontmostPaste"
        case .transcriptHistorySQLite: return "transcriptHistorySQLite"
        }
    }
}
