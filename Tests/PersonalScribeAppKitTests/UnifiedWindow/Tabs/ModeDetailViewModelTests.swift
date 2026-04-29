import XCTest
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

/// #090 — `ModeDetailViewModel.voiceModelPinID` getter +
/// `setVoiceModelPin` setter round-trip through the registry.
@MainActor
final class ModeDetailViewModelTests: XCTestCase {

    func testDeleteRemovesModeFromRegistry() throws {
        let custom = WorkflowMode(
            id: "delete-me",
            name: "Delete Me",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(mode: custom, registry: registry)

        XCTAssertEqual(registry.customModes.map(\.id), ["delete-me"])

        XCTAssertTrue(viewModel.delete())
        XCTAssertTrue(registry.customModes.isEmpty)
        XCTAssertNil(viewModel.lastError)
    }

    func testVoiceModelPinIDRoundTripsThroughRegistry() throws {
        let custom = WorkflowMode(
            id: "pin-rt",
            name: "Pin Round Trip",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(mode: custom, registry: registry)

        XCTAssertNil(viewModel.voiceModelPinID, "Fresh mode has no pin")

        viewModel.setVoiceModelPin("parakeet-tdt-ctc-110m")

        XCTAssertEqual(viewModel.voiceModelPinID, "parakeet-tdt-ctc-110m")
        // Persisted: registry now has the updated mode.
        let saved = registry.customModes.first { $0.id == "pin-rt" }
        guard case .transcriber(_, let savedID) = saved?.processors.first else {
            XCTFail("Expected .transcriber spec on persisted mode")
            return
        }
        XCTAssertEqual(savedID, "parakeet-tdt-ctc-110m")
    }
}
