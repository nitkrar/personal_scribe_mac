import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.11 — recipe-driven `WorkflowMode` (renamed from
/// `RecipeWorkflowMode` at #078.30b cutover). Tests pin the
/// three-role-list shape, the dictation built-in default, and
/// Codable round-trip.
final class WorkflowModeTests: XCTestCase {

    func testRecipeHoldsThreeRoleLists() {
        // The recipe carries three independently-typed lists per L20.
        // Constructing one with explicit lists and reading them back
        // pins the role separation.
        let recipe = WorkflowMode(
            id: "test-recipe",
            name: "Test Recipe",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertEqual(recipe.processors.count, 1)
        XCTAssertEqual(recipe.captureControllers.count, 1)
        XCTAssertEqual(recipe.outputSinks.count, 1)

        XCTAssertEqual(recipe.processors.first, .transcriber(kind: .asr))
        XCTAssertEqual(recipe.captureControllers.first, .manualHotkey)
        XCTAssertEqual(recipe.outputSinks.first, .transcriptHistorySQLite)
    }

    func testDictationDefaultIsBatchPipelineWithTranscriberAndClipboardSink() {
        let dictation = WorkflowMode.dictation

        XCTAssertEqual(dictation.id, "dictation")
        XCTAssertEqual(dictation.pipelineShape, .batch)
        XCTAssertEqual(dictation.processors, [.transcriber(kind: .asr)])

        // Clipboard sink must be present and reference the central
        // `ClipboardRestoreEnabled` setting via `.setting(...)`.
        let clipboardSink = dictation.outputSinks.first { sink in
            if case .clipboard = sink { return true }
            return false
        }
        XCTAssertNotNil(
            clipboardSink,
            "Dictation must include a clipboard output sink."
        )
        if case .clipboard(let restoreEnabled) = clipboardSink {
            guard case .setting(let key) = restoreEnabled else {
                XCTFail(
                    "Dictation clipboard sink must reference the global `ClipboardRestoreEnabled` setting via `.setting(...)`."
                )
                return
            }
            XCTAssertEqual(key.key, "ClipboardRestoreEnabled")
        }
    }

    func testRecipeCodableRoundTrip() throws {
        let original = WorkflowMode.dictation

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WorkflowMode.self, from: data)

        XCTAssertEqual(decoded, original)
    }
}
