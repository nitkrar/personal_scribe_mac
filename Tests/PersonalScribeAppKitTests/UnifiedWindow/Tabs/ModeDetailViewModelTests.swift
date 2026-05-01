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

    func testStreamingParametersRoundTripThroughRegistry() throws {
        let custom = WorkflowMode(
            id: "streaming-rt",
            name: "Streaming Round Trip",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite],
            streamingBehavior: StreamingBehaviorSpec(
                liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
                liveCursorEnabled: .setting(PreferenceKeys.streamingLiveCursorEnabled),
                secondPassEnabled: .setting(PreferenceKeys.streamingSecondPassEnabled)
            )
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.streamingASR] }
        )
        let viewModel = ModeDetailViewModel(mode: custom, registry: registry)

        viewModel.setLiveTranscriptCard(.override(false))
        viewModel.setLiveCursorStreaming(.override(true))
        viewModel.setAuthoritativeSecondPass(.override(false))

        XCTAssertEqual(viewModel.liveTranscriptCardParameter, .override(false))
        XCTAssertEqual(viewModel.liveCursorStreamingParameter, .override(true))
        XCTAssertEqual(viewModel.authoritativeSecondPassParameter, .override(false))

        let saved = registry.customModes.first { $0.id == "streaming-rt" }
        XCTAssertEqual(saved?.streamingBehavior?.liveCardEnabled, .override(false))
        XCTAssertEqual(saved?.streamingBehavior?.liveCursorEnabled, .override(true))
        XCTAssertEqual(saved?.streamingBehavior?.secondPassEnabled, .override(false))
    }
}
