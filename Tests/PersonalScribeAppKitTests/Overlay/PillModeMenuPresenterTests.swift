import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class PillModeMenuPresenterTests: XCTestCase {
    func testMenuUsesProviderModesAndMarksCurrent() {
        let modes = [WorkflowMode.dictation, makeMode(id: "notes", name: "Notes")]
        let presenter = PillModeMenuPresenter(
            modesProvider: { modes },
            currentModeIDProvider: { "notes" },
            onSelect: { _ in }
        )

        let menu = presenter.makeMenu()

        XCTAssertEqual(menu.items.map { $0.title }, ["Dictation", "Notes"])
        XCTAssertEqual(menu.items.map { $0.state }, [NSControl.StateValue.off, .on])
    }

    func testSelectionResolvesFreshProviderMode() async {
        let selected = ModeSelectionRecorder()
        let mode = makeMode(id: "notes", name: "Notes")
        let presenter = PillModeMenuPresenter(
            modesProvider: { [mode] },
            currentModeIDProvider: { nil },
            onSelect: { mode in await selected.record(mode.id) }
        )

        await presenter.selectMode(id: "notes")

        let selectedID = await selected.value()
        XCTAssertEqual(selectedID, "notes")
    }

    private func makeMode(id: String, name: String) -> WorkflowMode {
        WorkflowMode(
            id: id,
            name: name,
            glyph: "note.text",
            pipelineShape: WorkflowMode.dictation.pipelineShape,
            processors: WorkflowMode.dictation.processors,
            captureControllers: WorkflowMode.dictation.captureControllers,
            outputSinks: WorkflowMode.dictation.outputSinks
        )
    }
}

private actor ModeSelectionRecorder {
    private var selectedID: String?
    func record(_ id: String) { selectedID = id }
    func value() -> String? { selectedID }
}
