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

    func testStreamingEouSilenceThresholdRoundTripsThroughRegistry() throws {
        let custom = WorkflowMode(
            id: "streaming-threshold",
            name: "Streaming Threshold",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite],
            streamingBehavior: .defaultSettings
        )
        let store = InMemoryWorkflowModeStore(
            initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
        )
        let registry = try WorkflowModeRegistry(
            store: store,
            availableKindsProvider: { [.streamingASR] }
        )
        let viewModel = ModeDetailViewModel(mode: custom, registry: registry)

        viewModel.setEouSilenceThreshold(.override(1400))

        XCTAssertEqual(viewModel.eouSilenceThresholdParameter, .override(1400))
        XCTAssertEqual(
            registry.customModes.first { $0.id == "streaming-threshold" }?.streamingBehavior?.eouSilenceThresholdMs,
            .override(1400)
        )
    }

    func testLanguageRoundTripsThroughRegistry() throws {
        let custom = WorkflowMode(
            id: "lang-rt",
            name: "Language Round Trip",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
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
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
        )

        viewModel.setLanguage("ja")

        XCTAssertEqual(viewModel.selectedLanguage, "ja")
        XCTAssertEqual(
            registry.customModes.first { $0.id == "lang-rt" }?.language,
            Parameter<String?>.override("ja")
        )
    }

    func testLanguagePickerHiddenWhenModeUsesDefaultVoiceModel() throws {
        let custom = WorkflowMode(
            id: "lang-default",
            name: "Language Default",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
        )

        XCTAssertTrue(viewModel.languageOptions.isEmpty)
        XCTAssertNil(viewModel.selectedLanguage)
    }

    func testLanguagePickerHiddenWhenPinnedDescriptorIsMonolingual() throws {
        let custom = WorkflowMode(
            id: "lang-mono",
            name: "Language Mono",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitSmallEn217MB.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [BuiltInModelCatalog.whisperKitSmallEn217MB]
        )

        XCTAssertTrue(viewModel.languageOptions.isEmpty)
    }

    func testSetVoiceModelPinToDefaultClearsLanguage() throws {
        let custom = WorkflowMode(
            id: "lang-default-clear",
            name: "Language Default Clear",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
        )

        viewModel.setVoiceModelPin(nil)

        XCTAssertNil(viewModel.voiceModelPinID)
        XCTAssertNil(viewModel.selectedLanguage)
        XCTAssertNil(
            registry.customModes.first { $0.id == "lang-default-clear" }?.language
        )
    }

    func testSetVoiceModelPinClearsUnsupportedLanguageOnDescriptorSwitch() throws {
        let custom = WorkflowMode(
            id: "lang-switch-clear",
            name: "Language Switch Clear",
            language: Parameter<String?>.override("ga"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [
                BuiltInModelCatalog.whisperKitTiny,
                BuiltInModelCatalog.qwen3AsrF32,
            ]
        )

        viewModel.setVoiceModelPin(BuiltInModelCatalog.qwen3AsrF32.id)

        XCTAssertEqual(viewModel.voiceModelPinID, BuiltInModelCatalog.qwen3AsrF32.id)
        XCTAssertNil(viewModel.selectedLanguage)
        XCTAssertNil(
            registry.customModes.first { $0.id == "lang-switch-clear" }?.language
        )
    }

    func testSetVoiceModelPinPreservesSupportedLanguageOnDescriptorSwitch() throws {
        let custom = WorkflowMode(
            id: "lang-switch-keep",
            name: "Language Switch Keep",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [
                BuiltInModelCatalog.whisperKitTiny,
                BuiltInModelCatalog.qwen3AsrF32,
            ]
        )

        viewModel.setVoiceModelPin(BuiltInModelCatalog.qwen3AsrF32.id)

        XCTAssertEqual(viewModel.voiceModelPinID, BuiltInModelCatalog.qwen3AsrF32.id)
        XCTAssertEqual(viewModel.selectedLanguage, "ja")
        XCTAssertEqual(
            registry.customModes.first { $0.id == "lang-switch-keep" }?.language,
            Parameter<String?>.override("ja")
        )
    }

    func testSetRealtimeClearsLanguageWhenPinIsDropped() throws {
        let custom = WorkflowMode(
            id: "lang-realtime-clear",
            name: "Language Realtime Clear",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(
                initial: WorkflowModeDocument(defaultModeID: nil, customModes: [custom])
            ),
            availableKindsProvider: { [.asr, .streamingASR] }
        )
        let viewModel = ModeDetailViewModel(
            mode: custom,
            registry: registry,
            registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
        )

        viewModel.setRealtime(true)

        XCTAssertTrue(viewModel.realtimeOn)
        XCTAssertNil(viewModel.voiceModelPinID)
        XCTAssertNil(viewModel.selectedLanguage)
        XCTAssertNil(
            registry.customModes.first { $0.id == "lang-realtime-clear" }?.language
        )
    }
}
