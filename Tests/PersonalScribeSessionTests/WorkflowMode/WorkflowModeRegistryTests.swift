import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class WorkflowModeRegistryTests: XCTestCase {

    // MARK: - Resolution

    func testFreshRegistryExposesBuiltInDictationAsCurrent() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { Set(ModelKind.allCases) }
        )

        XCTAssertEqual(registry.defaultMode.id, "dictation")
        XCTAssertEqual(registry.currentMode.id, "dictation")
        XCTAssertEqual(registry.allModes.map(\.id), ["dictation"])
    }

    func testSetDefaultSwitchesDefaultModeAndPersists() throws {
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: nil,
                customModes: [Self.makeCustomDictation(id: "med-notes")]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        try registry.setDefault(id: "med-notes")

        XCTAssertEqual(registry.defaultMode.id, "med-notes")
        XCTAssertEqual(registry.currentMode.id, "med-notes")
        let persisted = try store.load()
        XCTAssertEqual(persisted.defaultModeID, "med-notes")
    }

    func testSetDefaultRejectsUnknownID() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        XCTAssertThrowsError(try registry.setDefault(id: "no-such-mode")) { error in
            XCTAssertEqual(
                error as? WorkflowModeRegistryError,
                .unknownMode("no-such-mode")
            )
        }
    }

    /// Renamed from `testSetActiveValidatesAvailableKinds` (#089 IMPL
    /// Stage H — same body, `setActive` → `setDefault`).
    func testSetDefaultValidatesAvailableKinds() throws {
        let custom = WorkflowMode(
            id: "needs-streaming",
            name: "Needs streaming",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: nil,
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] } // streamingASR NOT available
        )

        XCTAssertThrowsError(try registry.setDefault(id: "needs-streaming")) { error in
            guard let validationError = error as? WorkflowModeValidationError else {
                XCTFail("Expected WorkflowModeValidationError, got \(error)")
                return
            }
            XCTAssertEqual(validationError, .kindUnavailable(.streamingASR))
        }
    }

    func testSetCurrentSwitchesRuntimeWithoutPersisting() throws {
        let custom = Self.makeCustomDictation(id: "med-notes")
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: nil,
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        registry.setCurrent(id: "med-notes")

        XCTAssertEqual(registry.currentMode.id, "med-notes")
        // Default unchanged: setCurrent never writes the document.
        XCTAssertEqual(registry.defaultMode.id, "dictation")
        let persisted = try store.load()
        XCTAssertNil(persisted.defaultModeID)
    }

    func testSetCurrentUnknownIDIsSilentNoop() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        registry.setCurrent(id: "no-such-mode")

        XCTAssertEqual(registry.currentMode.id, "dictation")
    }

    // MARK: - saveCustom

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

    // MARK: - H-tests (#089 Stage H)

    /// H.1 — stale defaultModeID at init must scrub-and-persist; the
    /// resolve path is also implicitly covered (every test that reads
    /// `defaultMode` exercises it).
    func testInitClearsStaleDefaultModeID() throws {
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: "ghost-mode",
                customModes: []
            )
        )

        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        XCTAssertEqual(registry.defaultMode.id, "dictation")
        let persisted = try store.load()
        XCTAssertNil(persisted.defaultModeID,
                     "Stale defaultModeID must be cleared and written-through at init")
    }

    /// H.2 — skip-gaps default-name resolver (#089 L-14).
    func testCreatePresetSkipsNameGaps() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        // First save with "Dictation" — bare basename is free.
        let n1 = registry.nextAvailableName("Dictation")
        XCTAssertEqual(n1, "Dictation")
        try registry.saveCustom(Self.makeCustomDictation(id: "m1", name: n1))

        // Second save — bare basename is taken; bumps to "Dictation 2".
        let n2 = registry.nextAvailableName("Dictation")
        XCTAssertEqual(n2, "Dictation 2")
        try registry.saveCustom(Self.makeCustomDictation(id: "m2", name: n2))

        // Delete "Dictation" (id m1). Now: bare basename free again,
        // but "Dictation 2" still occupies the suffix space — skip-gaps
        // means the next name is "Dictation 3", NOT a reused
        // "Dictation".
        try registry.deleteCustom(id: "m1")
        let n3 = registry.nextAvailableName("Dictation")
        XCTAssertEqual(n3, "Dictation 3",
                       "Skip-gaps: must not reuse a name even when basename is free if a suffix is in use")
    }

    /// H.3 — deleting the default mode clears defaultModeID (does NOT
    /// fall back to dictation.id) and currentMode resolves through to
    /// the built-in fallback.
    func testDeleteDefaultClearsDefault() throws {
        let custom = Self.makeCustomDictation(id: "med-notes", name: "Medical Notes")
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: "med-notes",
                customModes: [custom]
            )
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        registry.setCurrent(id: "med-notes")
        XCTAssertEqual(registry.currentMode.id, "med-notes")

        try registry.deleteCustom(id: "med-notes")

        let persisted = try store.load()
        XCTAssertNil(persisted.defaultModeID,
                     "Deleting the default mode must clear defaultModeID, not point at dictation.id")
        XCTAssertEqual(registry.defaultMode.id, "dictation")
        XCTAssertEqual(registry.currentMode.id, "dictation")
    }

    /// H.4 — reorderCustom writes through the new array order.
    func testReorderPersistsThroughStore() throws {
        let store = InMemoryWorkflowModeStore()
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        try registry.saveCustom(Self.makeCustomDictation(id: "A", name: "A"))
        try registry.saveCustom(Self.makeCustomDictation(id: "B", name: "B"))
        try registry.saveCustom(Self.makeCustomDictation(id: "C", name: "C"))
        XCTAssertEqual(registry.customModes.map(\.id), ["A", "B", "C"])

        try registry.reorderCustom(from: 0, to: 2)

        let persisted = try store.load()
        XCTAssertEqual(persisted.customModes.map(\.id), ["B", "C", "A"],
                       "Reorder must rewrite the customModes array order on disk")
    }

    // MARK: - #027 — legacy id migration

    /// Init must rewrite any `custom-{UUID}`-style id (the pre-#027
    /// `Preset.materialize` format) into the new `{cleanName}-{suffix}`
    /// shape so transcript rows can recover a fallback display via
    /// `id.split(separator: "-").first`.
    func testInitRewritesLegacyCustomUUIDIDsIntoCleanNameSuffix() throws {
        let legacy = WorkflowMode(
            id: "custom-7a3f1c9e-0000-1111-2222-333333333333",
            name: "Project Notes",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: nil,
                customModes: [legacy]
            )
        )

        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let migrated = try XCTUnwrap(registry.customModes.first)
        XCTAssertFalse(WorkflowMode.isLegacyID(migrated.id),
                       "Legacy id must be rewritten in init")
        XCTAssertTrue(migrated.id.hasPrefix("Project Notes-"),
                      "New id should encode the clean user-facing name; got \(migrated.id)")

        // Migration must persist back through the store so the
        // rewrite happens once per legacy file, not on every launch.
        let persisted = try store.load()
        XCTAssertEqual(persisted.customModes.map(\.id), [migrated.id])
    }

    /// `defaultModeID` must follow the rewrite when it pointed at a
    /// migrated entry — otherwise the next default-mode resolution
    /// scrubs it as stale.
    func testInitMigrationRewritesDefaultModeIDReference() throws {
        let legacyID = "custom-aaaaaaaa-0000-1111-2222-333333333333"
        let legacy = WorkflowMode(
            id: legacyID,
            name: "Meeting",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: legacyID,
                customModes: [legacy]
            )
        )

        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )

        let migrated = try XCTUnwrap(registry.customModes.first)
        XCTAssertEqual(registry.defaultMode.id, migrated.id,
                       "defaultModeID must point at the rewritten id, not be scrubbed as stale")
    }

    /// Migration is idempotent: re-running init on an already-migrated
    /// document must NOT churn the ids.
    func testInitMigrationIsIdempotentAcrossRestarts() throws {
        let legacy = WorkflowMode(
            id: "custom-bbbbbbbb-0000-1111-2222-333333333333",
            name: "Notes",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(
                defaultModeID: nil,
                customModes: [legacy]
            )
        )

        _ = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        let firstPass = try store.load().customModes.map(\.id)

        _ = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        let secondPass = try store.load().customModes.map(\.id)

        XCTAssertEqual(firstPass, secondPass,
                       "Restart must not re-mint already-migrated ids")
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
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
    }
}
