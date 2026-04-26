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
        let custom = RecipeWorkflowMode(
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

    // MARK: - Helpers

    /// Custom mode that mirrors the built-in dictation shape but with a
    /// caller-chosen ID so it can be added without colliding with the
    /// built-in.
    private static func makeCustomDictation(
        id: String,
        name: String = "Custom Dictation"
    ) -> RecipeWorkflowMode {
        RecipeWorkflowMode(
            id: id,
            name: name,
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste]
        )
    }
}
