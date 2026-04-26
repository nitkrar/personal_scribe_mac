import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class WorkflowModeRegistryTests: XCTestCase {

    func testFreshRegistryExposesBuiltInDictationAsActive() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { Set(ModelKind.allCases) }
        )

        XCTAssertEqual(registry.activeMode.id, "dictation")
        XCTAssertEqual(registry.allModes.map(\.id), ["dictation"])
    }

    func testSetActiveSwitchesActiveModeAndPersists() throws {
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                activeModeID: nil,
                customModes: [Self.makeCustomDictation(id: "med-notes")]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        try registry.setActive(id: "med-notes")

        XCTAssertEqual(registry.activeMode.id, "med-notes")
        let persisted = try store.load()
        XCTAssertEqual(persisted.activeModeID, "med-notes")
    }

    func testSetActiveRejectsUnknownID() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        XCTAssertThrowsError(try registry.setActive(id: "no-such-mode")) { error in
            XCTAssertEqual(
                error as? WorkflowModeRegistryError,
                .unknownMode("no-such-mode")
            )
        }
    }

    func testSetActiveRejectsModeWithUnavailableKind() throws {
        let custom = WorkflowMode(
            id: "needs-streaming",
            name: "Needs streaming",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                activeModeID: nil,
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] } // streamingASR NOT available
        )

        XCTAssertThrowsError(try registry.setActive(id: "needs-streaming")) { error in
            guard let validationError = error as? WorkflowModeValidationError else {
                XCTFail("Expected WorkflowModeValidationError, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .kindUnavailable(.streamingASR))
        }
    }

    func testSaveCustomInsertsThenUpdatesByID() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let v1 = Self.makeCustomDictation(id: "med-notes", name: "Medical Notes")
        try registry.saveCustom(v1)
        XCTAssertEqual(registry.allModes.count, 2)

        let v2 = Self.makeCustomDictation(id: "med-notes", name: "Medical Notes (revised)")
        try registry.saveCustom(v2)
        XCTAssertEqual(registry.allModes.count, 2)
        XCTAssertEqual(registry.allModes.last?.name, "Medical Notes (revised)")
    }

    func testSaveCustomRejectsBuiltInID() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let collision = Self.makeCustomDictation(id: "dictation")
        XCTAssertThrowsError(try registry.saveCustom(collision)) { error in
            XCTAssertEqual(
                error as? WorkflowModeRegistryError,
                .builtInIDReserved("dictation")
            )
        }
    }

    func testDeleteCustomFallsBackToDictationWhenActive() throws {
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                activeModeID: "med-notes",
                customModes: [Self.makeCustomDictation(id: "med-notes")]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        try registry.deleteCustom(id: "med-notes")

        XCTAssertEqual(registry.activeMode.id, "dictation")
        XCTAssertEqual(registry.allModes.map(\.id), ["dictation"])
    }

    // MARK: - mutateActiveOrFork

    func testMutateActiveOrForkOnBuiltInForksToCustomAndSwitchesActive() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        XCTAssertEqual(registry.activeMode.id, "dictation")

        let result = try registry.mutateActiveOrFork { mode in
            // Append .vad to capture controllers (simulates Settings
            // toggling Auto-stop on).
            mode = WorkflowMode(
                id: mode.id,
                name: mode.name,
                pipelineShape: mode.pipelineShape,
                processors: mode.processors,
                captureControllers: [
                    .vad(
                        silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                        showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                        showAutoStoppedNotification: .setting(
                            PreferenceKeys.vadShowAutoStoppedNotification
                        )
                    ),
                ] + mode.captureControllers,
                outputSinks: mode.outputSinks
            )
        }

        XCTAssertEqual(result.id, "dictation-custom")
        XCTAssertEqual(result.name, "Dictation (custom)")
        XCTAssertEqual(registry.activeMode.id, "dictation-custom")
        XCTAssertEqual(registry.allModes.count, 2)
        // First capture controller is now .vad.
        if case .vad = result.captureControllers.first {
            // ok
        } else {
            XCTFail("Expected .vad to be first capture controller, got \(result.captureControllers)")
        }
    }

    func testMutateActiveOrForkOnCustomMutatesInPlaceWithoutForking() throws {
        let custom = WorkflowMode(
            id: "med-notes",
            name: "Medical Notes",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                activeModeID: "med-notes",
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let result = try registry.mutateActiveOrFork { mode in
            // Strip frontmostPaste (simulates Auto-paste toggle off).
            mode = WorkflowMode(
                id: mode.id,
                name: mode.name,
                pipelineShape: mode.pipelineShape,
                processors: mode.processors,
                captureControllers: mode.captureControllers,
                outputSinks: mode.outputSinks.filter { sink in
                    if case .frontmostPaste = sink { return false }
                    return true
                }
            )
        }

        XCTAssertEqual(result.id, "med-notes")
        XCTAssertEqual(registry.allModes.count, 2) // dictation + med-notes
        XCTAssertTrue(result.outputSinks.isEmpty)
    }

    // MARK: - Helpers

    /// Custom mode that mirrors the built-in dictation shape but with a
    /// caller-chosen ID so it can be added without colliding with the
    /// built-in.
    private static func makeCustomDictation(
        id: String,
        name: String = "Custom Dictation"
    ) -> WorkflowMode {
        WorkflowMode(
            id: id,
            name: name,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste]
        )
    }
}
