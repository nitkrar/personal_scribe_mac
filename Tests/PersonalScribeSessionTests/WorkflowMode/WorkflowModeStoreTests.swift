import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

final class WorkflowModeStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("WorkflowModeStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let tempDir, FileManager.default.fileExists(atPath: tempDir.path) {
            try FileManager.default.removeItem(at: tempDir)
        }
        try super.tearDownWithError()
    }

    func testLoadFromMissingFileReturnsDefaultDocument() throws {
        let store = WorkflowModeStore(baseDirectory: tempDir)
        let doc = try store.load()

        XCTAssertEqual(doc.schemaVersion, WorkflowModeDocument.currentSchemaVersion)
        XCTAssertNil(doc.defaultModeID)
        XCTAssertTrue(doc.customModes.isEmpty)
        // Crucially: load does NOT create the file just because it was
        // missing — only save does.
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: tempDir.appendingPathComponent("workflow-modes.json").path
            )
        )
    }

    func testSaveThenLoadRoundTrips() throws {
        let store = WorkflowModeStore(baseDirectory: tempDir)
        let original = WorkflowModeDocument(
            defaultModeID: "med-notes",
            customModes: [
                WorkflowMode(
                    id: "med-notes",
                    name: "Medical Notes",
                    pipelineShape: .batch,
                    processors: [.transcriber(kind: .asr)],
                    captureControllers: [.manualHotkey],
                    outputSinks: [.frontmostPaste(enabled: .override(true))]
                ),
            ]
        )

        try store.save(original)
        let loaded = try store.load()

        XCTAssertEqual(loaded, original)
    }

    func testSaveCreatesBaseDirectoryIfMissing() throws {
        // Use a nested path that does not exist yet.
        let nested = tempDir.appendingPathComponent("nested/deeper")
        let store = WorkflowModeStore(baseDirectory: nested)
        let doc = WorkflowModeDocument()

        try store.save(doc)

        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: nested.appendingPathComponent("workflow-modes.json").path
            )
        )
    }

    func testLoadOfCorruptDocumentThrowsDecodeFailed() throws {
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let url = tempDir.appendingPathComponent("workflow-modes.json")
        try Data("not-valid-json".utf8).write(to: url)
        let store = WorkflowModeStore(baseDirectory: tempDir)

        XCTAssertThrowsError(try store.load()) { error in
            guard case WorkflowModeStoreError.decodeFailed = error else {
                XCTFail("Expected decodeFailed, got \(error)")
                return
            }
        }
    }

    func testRegistryWiredAgainstDiskStorePersistsAcrossInits() throws {
        let store1 = WorkflowModeStore(baseDirectory: tempDir)
        let registry1 = try WorkflowModeRegistry(
            store: store1,
            availableKindsProvider: { [.asr] }
        )
        let custom = WorkflowMode(
            id: "med-notes",
            name: "Medical Notes",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )
        try registry1.saveCustom(custom)
        try registry1.setDefault(id: "med-notes")

        // Fresh registry on a new store reading the same disk path.
        let store2 = WorkflowModeStore(baseDirectory: tempDir)
        let registry2 = try WorkflowModeRegistry(
            store: store2,
            availableKindsProvider: { [.asr] }
        )

        XCTAssertEqual(registry2.defaultMode.id, "med-notes")
        XCTAssertEqual(registry2.currentMode.id, "med-notes")
        XCTAssertEqual(registry2.allModes.map(\.id), ["dictation", "med-notes"])
    }
}
