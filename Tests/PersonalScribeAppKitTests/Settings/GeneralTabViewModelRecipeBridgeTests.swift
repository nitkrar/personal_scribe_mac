import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// #078.33 / L27 — `GeneralTabViewModel`'s three structural toggles
/// bridge to the active recipe via `WorkflowModeRegistry`. Each setter
/// continues to write to `UserDefaults` (legacy fallback per plan) AND
/// mutates the active recipe (or forks the built-in `Dictation` if
/// active is a built-in). Tests pin both the structural recipe change
/// and the dual-write.
@MainActor
final class GeneralTabViewModelRecipeBridgeTests: XCTestCase {
    private let suiteName = "GeneralTabViewModelRecipeBridgeTests"

    private func isolatedDefaults() -> UserDefaults {
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    private func makeRegistry() throws -> WorkflowModeRegistry {
        try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { [.asr] }
        )
    }

    // MARK: - Auto-paste

    func testSetAutoPasteEnabledFalseRemovesFrontmostPasteFromActiveRecipe() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        // Sanity: built-in Dictation includes `.frontmostPaste` by default.
        XCTAssertTrue(
            registry.activeMode.outputSinks.contains(where: { sink in
                if case .frontmostPaste = sink { return true }
                return false
            })
        )

        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        viewModel.setAutoPasteEnabled(false)

        XCTAssertFalse(
            registry.activeMode.outputSinks.contains(where: { sink in
                if case .frontmostPaste = sink { return true }
                return false
            }),
            "Active recipe should no longer contain .frontmostPaste after toggle off."
        )
        // Dual-write: UserDefaults still reflects the toggle state.
        XCTAssertFalse(AutoPasteEnabledPreference.resolve(from: defaults))
    }

    func testSetAutoPasteEnabledTrueAddsFrontmostPasteAfterClipboardSink() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        // First flip OFF to remove `.frontmostPaste` (forks Dictation).
        viewModel.setAutoPasteEnabled(false)
        XCTAssertFalse(
            registry.activeMode.outputSinks.contains(where: { sink in
                if case .frontmostPaste = sink { return true }
                return false
            })
        )

        // Then flip ON — should re-insert `.frontmostPaste` immediately
        // after the clipboard sink so paste reads the freshly-written
        // transcript.
        viewModel.setAutoPasteEnabled(true)

        let sinks = registry.activeMode.outputSinks
        let clipboardIdx = sinks.firstIndex(where: { sink in
            if case .clipboard = sink { return true }
            return false
        })
        let pasteIdx = sinks.firstIndex(where: { sink in
            if case .frontmostPaste = sink { return true }
            return false
        })
        XCTAssertNotNil(clipboardIdx)
        XCTAssertNotNil(pasteIdx)
        XCTAssertEqual(pasteIdx, clipboardIdx.map { $0 + 1 })
        XCTAssertTrue(AutoPasteEnabledPreference.resolve(from: defaults))
    }

    func testSetAutoPasteEnabledOnBuiltInForksToCustomMode() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        XCTAssertEqual(registry.activeMode.id, "dictation")

        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        viewModel.setAutoPasteEnabled(false)

        XCTAssertNotEqual(
            registry.activeMode.id, "dictation",
            "Mutating a built-in should fork to a new custom mode."
        )
        XCTAssertEqual(registry.allModes.count, 2)
    }

    // MARK: - VAD master

    func testSetVadAutoStopEnabledTrueAddsVadCaptureControllerWithSettingParameters() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        // Sanity: built-in Dictation has no `.vad`.
        XCTAssertFalse(
            registry.activeMode.captureControllers.contains(where: { controller in
                if case .vad = controller { return true }
                return false
            })
        )

        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        viewModel.setVadAutoStopEnabled(true)

        let controllers = registry.activeMode.captureControllers
        guard
            case let .vad(silenceThreshold, showWarning, showAutoStoppedNotification) =
                controllers.first
        else {
            XCTFail("Expected first capture controller to be .vad, got \(controllers)")
            return
        }
        // Parameters defer to global settings (per user's stated model:
        // "VAD enabled is mode-level, threshold/warn/notify are settings").
        XCTAssertEqual(silenceThreshold, .setting(PreferenceKeys.vadSilenceThreshold))
        XCTAssertEqual(showWarning, .setting(PreferenceKeys.vadShowStoppingWarning))
        XCTAssertEqual(
            showAutoStoppedNotification,
            .setting(PreferenceKeys.vadShowAutoStoppedNotification)
        )
        XCTAssertTrue(VadAutoStopEnabledPreference.resolve(from: defaults))
    }

    func testSetVadAutoStopEnabledFalseRemovesVadFromActiveRecipe() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        // First add VAD.
        viewModel.setVadAutoStopEnabled(true)
        XCTAssertTrue(
            registry.activeMode.captureControllers.contains(where: { controller in
                if case .vad = controller { return true }
                return false
            })
        )

        // Then remove.
        viewModel.setVadAutoStopEnabled(false)
        XCTAssertFalse(
            registry.activeMode.captureControllers.contains(where: { controller in
                if case .vad = controller { return true }
                return false
            })
        )
        // `.manualHotkey` survives — only `.vad` is structural to this toggle.
        XCTAssertTrue(
            registry.activeMode.captureControllers.contains(.manualHotkey)
        )
        XCTAssertFalse(VadAutoStopEnabledPreference.resolve(from: defaults))
    }

    // MARK: - Restore clipboard

    func testSetClipboardRestoreEnabledWritesOverrideOnClipboardSink() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        // Sanity: built-in Dictation references the global setting via
        // `.setting(...)` for restoreEnabled, NOT `.override`.
        let initialClipboard = registry.activeMode.outputSinks.first { sink in
            if case .clipboard = sink { return true }
            return false
        }
        guard case .clipboard(let initialParam) = initialClipboard else {
            XCTFail("Expected clipboard sink in built-in dictation.")
            return
        }
        if case .override = initialParam {
            XCTFail("Built-in dictation should reference .setting, not .override.")
        }

        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        viewModel.setClipboardRestoreEnabled(false)

        let resolvedClipboard = registry.activeMode.outputSinks.first { sink in
            if case .clipboard = sink { return true }
            return false
        }
        guard case .clipboard(let restoreEnabled) = resolvedClipboard else {
            XCTFail("Expected clipboard sink to remain in active recipe.")
            return
        }
        XCTAssertEqual(
            restoreEnabled, .override(false),
            "Toggle should write Parameter.override on the clipboard sink (per #078.33 plan)."
        )
        XCTAssertFalse(ClipboardRestoreEnabledPreference.resolve(from: defaults))
    }

    func testSetClipboardRestoreEnabledFlipsOverrideValueWhenAlreadyOverridden() throws {
        let defaults = isolatedDefaults()
        let registry = try makeRegistry()
        let viewModel = GeneralTabViewModel(
            defaults: defaults,
            workflowModeRegistry: registry
        )

        viewModel.setClipboardRestoreEnabled(false)
        viewModel.setClipboardRestoreEnabled(true)

        let resolvedClipboard = registry.activeMode.outputSinks.first { sink in
            if case .clipboard = sink { return true }
            return false
        }
        guard case .clipboard(let restoreEnabled) = resolvedClipboard else {
            XCTFail("Expected clipboard sink to remain in active recipe.")
            return
        }
        XCTAssertEqual(restoreEnabled, .override(true))
    }

    // MARK: - Nil-registry back-compat

    func testNilRegistryDegradesToUserDefaultsOnlyBehavior() throws {
        let defaults = isolatedDefaults()
        // No registry — exercises the back-compat path used by tests
        // that don't care about the recipe bridge.
        let viewModel = GeneralTabViewModel(defaults: defaults)

        viewModel.setAutoPasteEnabled(false)
        viewModel.setVadAutoStopEnabled(true)
        viewModel.setClipboardRestoreEnabled(false)

        XCTAssertFalse(AutoPasteEnabledPreference.resolve(from: defaults))
        XCTAssertTrue(VadAutoStopEnabledPreference.resolve(from: defaults))
        XCTAssertFalse(ClipboardRestoreEnabledPreference.resolve(from: defaults))
    }
}
