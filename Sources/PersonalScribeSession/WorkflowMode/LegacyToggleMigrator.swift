import Foundation
import PersonalScribeCore

/// One-shot migration from the pre-#078 global toggles
/// (`VadAutoStopEnabled`, `AutoPasteEnabled`) into the recipe model
/// per L18 + L27.
///
/// Why this exists: the built-in `WorkflowMode.dictation` has
/// **no `VadController`** and includes `.frontmostPaste`. Today's users
/// have legacy `VadAutoStopEnabled = true` (default), so they expect
/// VAD on. Without migration, post-#078 they'd silently lose VAD —
/// per `feedback_bundle_pref_alignment.md` that's "the 'default' is a
/// lie" failure mode.
///
/// Strategy: create a forked custom mode `dictation-migrated` only when
/// the user's legacy state **differs** from what the built-in dictation
/// would produce. If the user explicitly matched the built-in (turned
/// VAD off, paste on), no migration needed — built-in answers it.
///
/// VAD parameters (silenceThreshold / showWarning /
/// showAutoStoppedNotification) flow through as `Parameter.setting(...)`
/// references, so toggling those preferences in the legacy Settings
/// surface continues to work post-cutover.
///
/// `ClipboardRestoreEnabled` and `MuteOutputWhileRecording` /
/// `BackgroundLaunchPreference` are NOT migrated to recipes — clipboard
/// restore is already a `Parameter.setting(...)` on the built-in
/// dictation; the latter two stay global per L27.
///
/// Idempotent via `defaults.bool(forKey: migrationFlagKey)`. Run once
/// at first composition-root setup; subsequent runs no-op.
public final class LegacyToggleMigrator: @unchecked Sendable {
    public static let migrationFlagKey = "LegacyToggleMigrationApplied_v1"
    public static let migratedModeID = "dictation-migrated"
    public static let migratedModeName = "Dictation (migrated)"

    private let registry: WorkflowModeRegistry
    private let defaults: UserDefaults

    public init(
        registry: WorkflowModeRegistry,
        defaults: UserDefaults = .standard
    ) {
        self.registry = registry
        self.defaults = defaults
    }

    public func runIfNeeded() throws {
        guard !defaults.bool(forKey: Self.migrationFlagKey) else {
            return
        }

        let legacy = LegacyToggleSnapshot.read(from: defaults)
        let needsFork = legacy.differsFromBuiltInDictation

        if needsFork {
            let migrated = makeMigratedDictation(legacy: legacy)
            try registry.saveCustom(migrated)
            try registry.setActive(id: migrated.id)
        }

        defaults.set(true, forKey: Self.migrationFlagKey)
    }

    // MARK: - Internals

    private func makeMigratedDictation(legacy: LegacyToggleSnapshot) -> WorkflowMode {
        var captureControllers: [CaptureControllerSpec] = []
        if legacy.vadAutoStopEnabled {
            captureControllers.append(
                .vad(
                    silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                    showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                    showAutoStoppedNotification: .setting(
                        PreferenceKeys.vadShowAutoStoppedNotification
                    )
                )
            )
        }
        captureControllers.append(.manualHotkey)

        var outputSinks: [OutputSinkSpec] = [
            .clipboard(restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)),
        ]
        if legacy.autoPasteEnabled {
            outputSinks.append(.frontmostPaste)
        }
        outputSinks.append(.transcriptHistorySQLite)

        return WorkflowMode(
            id: Self.migratedModeID,
            name: Self.migratedModeName,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: captureControllers,
            outputSinks: outputSinks
        )
    }
}

/// Snapshot of the legacy toggle state used by the migrator. Exposed
/// for testability (tests can construct the snapshot directly without
/// seeding `UserDefaults`).
public struct LegacyToggleSnapshot: Equatable, Sendable {
    public let vadAutoStopEnabled: Bool
    public let autoPasteEnabled: Bool

    public init(vadAutoStopEnabled: Bool, autoPasteEnabled: Bool) {
        self.vadAutoStopEnabled = vadAutoStopEnabled
        self.autoPasteEnabled = autoPasteEnabled
    }

    public static func read(from defaults: UserDefaults) -> LegacyToggleSnapshot {
        LegacyToggleSnapshot(
            vadAutoStopEnabled: defaults.object(forKey: "VadAutoStopEnabled") as? Bool ?? true,
            autoPasteEnabled: defaults.object(forKey: "AutoPasteEnabled") as? Bool ?? true
        )
    }

    /// Built-in `WorkflowMode.dictation` has NO VAD and paste IS
    /// enabled. State that doesn't match that needs a forked recipe.
    public var differsFromBuiltInDictation: Bool {
        vadAutoStopEnabled != false || autoPasteEnabled != true
    }
}
