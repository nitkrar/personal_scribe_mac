import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

/// The modes list hands SwiftUI's `.onMove` / swipe / context-menu
/// actions straight to these methods, so the index conversion and the
/// registry round-trip are pinned here.
@MainActor
final class ModesListViewModelTests: XCTestCase {
    func testReorderMovesModeDownUsingSwiftUIOnMoveIndices() throws {
        let (viewModel, registry) = try makeViewModel(ids: ["a", "b", "c", "d"])

        // SwiftUI .onMove: dragging "b" below "d" reports destination 4.
        viewModel.reorder(from: IndexSet(integer: 1), to: 4)

        XCTAssertEqual(registry.customModes.map(\.id), ["a", "c", "d", "b"])
        XCTAssertNil(viewModel.lastError)
    }

    func testReorderMovesModeUpUsingSwiftUIOnMoveIndices() throws {
        let (viewModel, registry) = try makeViewModel(ids: ["a", "b", "c", "d"])

        viewModel.reorder(from: IndexSet(integer: 3), to: 1)

        XCTAssertEqual(registry.customModes.map(\.id), ["a", "d", "b", "c"])
    }

    func testDeleteRemovesModeFromRegistry() throws {
        let (viewModel, registry) = try makeViewModel(ids: ["a", "b"])

        viewModel.delete(registry.customModes[0])

        XCTAssertEqual(registry.customModes.map(\.id), ["b"])
        XCTAssertNil(viewModel.lastError)
    }

    private func makeViewModel(ids: [String]) throws -> (ModesListViewModel, WorkflowModeRegistry) {
        let modes = ids.map { id in
            WorkflowMode(
                id: id,
                name: "Mode \(id)",
                pipelineShape: .batch,
                processors: [.transcriber(kind: .asr)],
                captureControllers: [.manualHotkey],
                outputSinks: [.transcriptHistorySQLite]
            )
        }
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: modes)
            ),
            availableKindsProvider: { [.asr] }
        )
        let suiteName = "ModesListViewModelTests.\(UUID().uuidString)"
        let modelService = ActiveModelService(
            defaults: UserDefaults(suiteName: suiteName)!,
            physicalMemoryBytes: 16_000_000_000,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        return (ModesListViewModel(registry: registry, modelService: modelService), registry)
    }
}
