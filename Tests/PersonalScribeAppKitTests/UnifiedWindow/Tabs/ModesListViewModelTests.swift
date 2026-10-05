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

    func testVoiceModelCaptionNamesPinnedModel() throws {
        let pinned = BuiltInModelCatalog.parakeetTDT06Bv3
        let (viewModel, _, _) = try makeViewModel(modes: [mode(id: "a", pin: pinned.id)])

        XCTAssertEqual(viewModel.voiceModelCaptionByID["a"], pinned.displayName)
    }

    func testVoiceModelCaptionNamesGloballyActiveModelWhenUnpinned() throws {
        let (viewModel, _, modelService) = try makeViewModel(modes: [mode(id: "a", pin: nil)])
        let active = BuiltInModelCatalog.parakeetTDTCTC110M

        viewModel.startObserving()
        modelService.setActive(active, forKind: .asr)
        let expectation = expectation(description: "caption follows active model")
        DispatchQueue.main.async { expectation.fulfill() }
        wait(for: [expectation], timeout: 1)

        XCTAssertEqual(viewModel.voiceModelCaptionByID["a"], active.displayName)
    }

    private func mode(id: String, pin: String?) -> WorkflowMode {
        WorkflowMode(
            id: id,
            name: "Mode \(id)",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr, descriptorID: pin)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
    }

    private func makeViewModel(ids: [String]) throws -> (ModesListViewModel, WorkflowModeRegistry) {
        let (viewModel, registry, _) = try makeViewModel(modes: ids.map { mode(id: $0, pin: nil) })
        return (viewModel, registry)
    }

    private func makeViewModel(
        modes: [WorkflowMode]
    ) throws -> (ModesListViewModel, WorkflowModeRegistry, ActiveModelService) {
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
        return (
            ModesListViewModel(registry: registry, modelService: modelService),
            registry,
            modelService
        )
    }
}
