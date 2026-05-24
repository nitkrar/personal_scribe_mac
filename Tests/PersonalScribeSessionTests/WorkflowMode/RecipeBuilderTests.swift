import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

@MainActor
final class RecipeBuilderTests: XCTestCase {

    nonisolated(unsafe) private var defaults: UserDefaults!
    nonisolated(unsafe) private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "RecipeBuilderTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    func testBuilderResolvesActiveAsrDescriptorEagerly() throws {
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(.dictation)

        XCTAssertEqual(bound.recipeID, "dictation")
        XCTAssertEqual(bound.processors.count, 1)
        guard case .transcriber = bound.processors[0] else {
            XCTFail("Expected .transcriber, got \(bound.processors[0])")
            return
        }
        XCTAssertEqual(provider.transcriberRequests.map(\.id), [BuiltInModelCatalog.parakeetTDT06Bv2.id])
    }

    func testBuilderThrowsWhenAsrKindHasNoActive() throws {
        let service = makeServiceWithActive(asr: nil)
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        XCTAssertThrowsError(try builder.build(.dictation)) { error in
            XCTAssertEqual(error as? RecipeBuildError, .kindHasNoActiveDescriptor(.asr))
        }
    }

    func testBuilderResolvesParameterOverrideAndSettingFallback() throws {
        defaults.set(2.5, forKey: PreferenceKeys.vadSilenceThreshold.key)
        let service = makeServiceWithActive(asr: BuiltInModelCatalog.parakeetTDT06Bv2.id)
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        // Recipe with VAD: silence threshold via setting (resolves to
        // 2.5s from defaults), showWarning via override (forces true).
        let mode = WorkflowMode(
            id: "vad-mode",
            name: "VAD Mode",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [
                .vad(
                    enabled: .override(true),
                    silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                    showWarning: .override(true),
                    showAutoStoppedNotification: .setting(
                        PreferenceKeys.vadShowAutoStoppedNotification
                    )
                ),
                .manualHotkey,
            ],
            outputSinks: [.frontmostPaste(enabled: .override(true))]
        )

        let bound = try builder.build(mode)

        guard case .vad(let enabled, let silenceThreshold, let showWarning, let showAutoStopped) = bound.captureControllers[0] else {
            XCTFail("Expected .vad first capture controller, got \(bound.captureControllers)")
            return
        }
        XCTAssertTrue(enabled)
        XCTAssertEqual(silenceThreshold, 2.5)
        XCTAssertTrue(showWarning)
        XCTAssertFalse(showAutoStopped) // setting key default: false
    }

    func testPinnedDescriptorOverridesActiveDescriptor() throws {
        // #090: when a `.transcriber` pins a descriptorID, RecipeBuilder
        // resolves to the pinned descriptor regardless of which model is
        // globally active for that kind. Active = v2; pinned = 110M.
        // Builder must pass 110M (the pinned id) to the provider.
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let pinned = WorkflowMode(
            id: "pinned",
            name: "Pinned",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.parakeetTDTCTC110M.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        _ = try builder.build(pinned)

        XCTAssertEqual(
            provider.transcriberRequests.map(\.id),
            [BuiltInModelCatalog.parakeetTDTCTC110M.id]
        )
    }

    func testPinnedDiarizedTurnsTranscriberLegOverridesActiveDescriptor() throws {
        // #090: the `.diarizedTurns` ASR leg honors its
        // `transcriberDescriptorID` pin. Diarizer leg has no pin slot
        // in #090, so it still late-binds via the active diarization
        // descriptor.
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            diarization: BuiltInModelCatalog.speakerDiarization.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let pinned = WorkflowMode(
            id: "pinned-meeting",
            name: "Pinned Meeting",
            pipelineShape: .batch,
            processors: [
                .diarizedTurns(
                    diarizerKind: .diarization,
                    transcriberKind: .asr,
                    transcriberDescriptorID: BuiltInModelCatalog.parakeetTDTCTC110M.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        _ = try builder.build(pinned)

        // ASR leg used the pin (110M), not the active (v2).
        XCTAssertEqual(
            provider.transcriberRequests.map(\.id),
            [BuiltInModelCatalog.parakeetTDTCTC110M.id]
        )
    }

    func testMidBuildSetActiveOnServiceDoesNotAffectAlreadyBoundRecipe() throws {
        // Per L25: descriptor binding is eager-at-pipeline-build. Once
        // the recipe is built, mid-session setActive must not mutate it.
        let service = makeServiceWithActive(asr: BuiltInModelCatalog.parakeetTDT06Bv2.id)
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(.dictation)

        // Now switch the active descriptor.
        service.setActive(BuiltInModelCatalog.parakeetTDTCTC110M, forKind: .asr)

        // The bound recipe still references the original descriptor.
        XCTAssertEqual(provider.transcriberRequests.map(\.id), [BuiltInModelCatalog.parakeetTDT06Bv2.id])
        XCTAssertEqual(bound.processors.count, 1)
    }

    func testStreamingSecondPassUsesActiveASRWhenStreamingIsParakeetEOU() throws {
        defaults.set(false, forKey: PreferenceKeys.streamingLiveCardEnabled.key)
        defaults.set(true, forKey: PreferenceKeys.streamingLiveCursorEnabled.key)
        defaults.set(true, forKey: PreferenceKeys.streamingSecondPassEnabled.key)

        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.whisperCppTiny.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(
            Preset.streamingDictation.materialize(name: "Streaming Dictation")
        )

        XCTAssertEqual(
            bound.streamingBehavior,
            BoundStreamingBehavior(
                liveCardEnabled: false,
                liveCursorEnabled: true,
                secondPassEnabled: true
            )
        )
        XCTAssertNotNil(bound.streamingSecondPassTranscriber)
        XCTAssertEqual(
            provider.transcriberRequests.map(\.id),
            [BuiltInModelCatalog.whisperCppTiny.id]
        )
        XCTAssertEqual(
            provider.streamingTranscriberRequests.map(\.id),
            [BuiltInModelCatalog.parakeetEou160ms.id]
        )
    }

    func testStreamingSecondPassForcesWhisperCppWhenStreamingIsWhisperCpp() throws {
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )
        let mode = makePinnedStreamingMode(
            descriptorID: BuiltInModelCatalog.whisperCppTiny.id,
            secondPassEnabled: true
        )

        let bound = try builder.build(mode)
        let streamingProcessor = try XCTUnwrap(
            bound.processors.compactMap { processor in
                if case .streamingTranscriber(let transcriber) = processor {
                    return transcriber
                }
                return nil
            }.first
        )
        let secondPass = try XCTUnwrap(bound.streamingSecondPassTranscriber)

        XCTAssertEqual(
            provider.streamingTranscriberRequests.map(\.id),
            [BuiltInModelCatalog.whisperCppTiny.id]
        )
        XCTAssertEqual(
            provider.transcriberRequests.map(\.id),
            [BuiltInModelCatalog.whisperCppTiny.id]
        )
        // #100 C4: lock the second half of the contract — when streaming
        // is whisper.cpp, the active .asr descriptor (parakeet TDT here)
        // MUST be ignored entirely. Without this assertion the test
        // passes silently if the force-rule degraded to "prefer
        // whisper.cpp but also request parakeet on the side."
        XCTAssertFalse(
            provider.transcriberRequests.contains { $0.id == BuiltInModelCatalog.parakeetTDT06Bv2.id },
            "Active .asr descriptor must NOT be requested when streaming is whisper.cpp"
        )
        XCTAssertTrue((streamingProcessor as AnyObject) === (secondPass as AnyObject))
    }

    func testBuilderPreservesFrontmostPasteWhenLiveCursorEnabled() throws {
        defaults.set(false, forKey: PreferenceKeys.streamingLiveCardEnabled.key)
        defaults.set(true, forKey: PreferenceKeys.streamingLiveCursorEnabled.key)
        defaults.set(false, forKey: PreferenceKeys.streamingSecondPassEnabled.key)
        defaults.set(true, forKey: PreferenceKeys.autoPasteEnabled.key)

        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(
            Preset.streamingDictation.materialize(name: "Streaming Dictation")
        )

        XCTAssertTrue(bound.streamingBehavior?.liveCursorEnabled == true)
        // #098: `.frontmostPaste` survives even when liveCursor=true.
        // Both sinks fire; user picks which output they keep.
        let pasteSinks = bound.outputSinks.filter { sink in
            if case .frontmostPaste = sink {
                return true
            }
            return false
        }
        XCTAssertEqual(
            pasteSinks.count,
            1,
            "Expected .frontmostPaste to survive when liveCursorEnabled = true; got \(bound.outputSinks)"
        )
        // Sanity: clipboard sink should still be present.
        let clipboardSinks = bound.outputSinks.filter { sink in
            if case .clipboard = sink {
                return true
            }
            return false
        }
        XCTAssertEqual(clipboardSinks.count, 1, "Clipboard sink should also be present")
    }

    func testBuilderRetainsFrontmostPasteWhenLiveCursorDisabled() throws {
        defaults.set(true, forKey: PreferenceKeys.streamingLiveCardEnabled.key)
        defaults.set(false, forKey: PreferenceKeys.streamingLiveCursorEnabled.key)
        defaults.set(false, forKey: PreferenceKeys.streamingSecondPassEnabled.key)
        defaults.set(true, forKey: PreferenceKeys.autoPasteEnabled.key)

        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(
            Preset.streamingDictation.materialize(name: "Streaming Dictation")
        )

        XCTAssertTrue(bound.streamingBehavior?.liveCursorEnabled == false)
        let pasteSinks = bound.outputSinks.filter { sink in
            if case .frontmostPaste = sink {
                return true
            }
            return false
        }
        XCTAssertEqual(
            pasteSinks.count,
            1,
            "Expected .frontmostPaste to survive when liveCursorEnabled = false; got \(bound.outputSinks)"
        )
    }

    func testStreamingSecondPassReturnsNilWhenSecondPassDisabled() throws {
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.whisperCppTiny.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )
        let mode = makePinnedStreamingMode(
            descriptorID: BuiltInModelCatalog.parakeetEou160ms.id,
            secondPassEnabled: false
        )

        let bound = try builder.build(mode)

        XCTAssertNil(bound.streamingSecondPassTranscriber)
        XCTAssertEqual(provider.transcriberRequests.count, 0)
        XCTAssertEqual(
            provider.streamingTranscriberRequests.map(\.id),
            [BuiltInModelCatalog.parakeetEou160ms.id]
        )
    }

    func testStreamingSecondPassReturnsNilWhenNoActiveASRAvailableForNonWhisperCppStreaming() throws {
        defaults.set(true, forKey: PreferenceKeys.streamingSecondPassEnabled.key)

        let service = makeServiceWithActive(
            asr: nil,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )

        let bound = try builder.build(
            Preset.streamingDictation.materialize(name: "Streaming Dictation")
        )

        XCTAssertEqual(
            bound.streamingBehavior,
            BoundStreamingBehavior(
                liveCardEnabled: true,
                liveCursorEnabled: false,
                secondPassEnabled: true
            )
        )
        XCTAssertNil(bound.streamingSecondPassTranscriber)
        XCTAssertEqual(provider.transcriberRequests.count, 0)
        XCTAssertEqual(
            provider.streamingTranscriberRequests.map(\.id),
            [BuiltInModelCatalog.parakeetEou160ms.id]
        )
    }

    // MARK: - Helpers

    private func makeServiceWithActive(
        asr asrID: String?,
        streamingAsr streamingAsrID: String? = nil,
        diarization diarizationID: String? = nil
    ) -> ActiveModelService {
        let preference = Preference<[ModelKind: String]>(
            key: "RecipeBuilderTests-\(suiteName ?? "ActiveIDs")",
            default: [:],
            defaults: defaults
        )
        var seed: [ModelKind: String] = [:]
        if let asrID { seed[.asr] = asrID }
        if let streamingAsrID { seed[.streamingASR] = streamingAsrID }
        if let diarizationID { seed[.diarization] = diarizationID }
        if !seed.isEmpty {
            preference.persist(seed)
        }
        return ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
    }

    func testBuilderForcesLiveCursorOffForWhisperCppStreaming() throws {
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.whisperCppTiny.id,
            streamingAsr: BuiltInModelCatalog.whisperCppTiny.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )
        // Mode asks for liveCursorEnabled=true; whisper.cpp gate should
        // force it off because re-decode jitter produces duplicate EoU
        // chunks that paste irrevocably.
        let mode = makePinnedStreamingMode(
            descriptorID: BuiltInModelCatalog.whisperCppTiny.id,
            secondPassEnabled: false,
            liveCursorEnabled: true
        )

        let bound = try builder.build(mode)

        XCTAssertEqual(bound.streamingBehavior?.liveCursorEnabled, false)
        XCTAssertEqual(bound.streamingBehavior?.liveCardEnabled, true)
    }

    func testBuilderPreservesLiveCursorForNonWhisperCppStreaming() throws {
        let service = makeServiceWithActive(
            asr: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            streamingAsr: BuiltInModelCatalog.parakeetEou160ms.id
        )
        let provider = StubProcessorProvider()
        let builder = RecipeBuilder(
            modelService: service,
            processorProvider: provider,
            defaults: defaults
        )
        let mode = makePinnedStreamingMode(
            descriptorID: BuiltInModelCatalog.parakeetEou160ms.id,
            secondPassEnabled: false,
            liveCursorEnabled: true
        )

        let bound = try builder.build(mode)

        XCTAssertEqual(bound.streamingBehavior?.liveCursorEnabled, true)
    }

    private func makePinnedStreamingMode(
        descriptorID: String,
        secondPassEnabled: Bool,
        liveCursorEnabled: Bool = false
    ) -> WorkflowMode {
        WorkflowMode(
            id: "streaming-pinned-\(descriptorID)",
            name: "Streaming Pinned",
            pipelineShape: .streaming,
            processors: [.streamingTranscriber(kind: .streamingASR, descriptorID: descriptorID)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite],
            streamingBehavior: StreamingBehaviorSpec(
                liveCardEnabled: .override(true),
                liveCursorEnabled: .override(liveCursorEnabled),
                secondPassEnabled: .override(secondPassEnabled)
            )
        )
    }
}

/// In-memory stub of `ModelBoundProcessorProviding` that records the
/// descriptors passed to each accessor.
private final class StubProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var transcribers: [String: any Transcriber] = [:]
    private var streamingTranscribers: [String: any StreamingTranscriber] = [:]
    private var sharedWhisperCppAdapters: [String: SharedWhisperCppAdapter] = [:]
    private(set) var transcriberRequests: [ModelDescriptor] = []
    private(set) var streamingTranscriberRequests: [ModelDescriptor] = []

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber {
        lock.withLock {
            transcriberRequests.append(descriptor)
            if descriptor.engine == .whisperCpp {
                if let existing = sharedWhisperCppAdapters[descriptor.id] {
                    return existing
                }
                let new = SharedWhisperCppAdapter()
                sharedWhisperCppAdapters[descriptor.id] = new
                return new
            }
            if let existing = transcribers[descriptor.id] {
                return existing
            }
            let new = StubTranscriber()
            transcribers[descriptor.id] = new
            return new
        }
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        lock.withLock {
            streamingTranscriberRequests.append(descriptor)
            if descriptor.engine == .whisperCpp {
                if let existing = sharedWhisperCppAdapters[descriptor.id] {
                    return existing
                }
                let new = SharedWhisperCppAdapter()
                sharedWhisperCppAdapters[descriptor.id] = new
                return new
            }
            if let existing = streamingTranscribers[descriptor.id] {
                return existing
            }
            let new = StubStreamingTranscriber()
            streamingTranscribers[descriptor.id] = new
            return new
        }
    }

    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        StubDiarizer()
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool { true }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {}

    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {}

    func evict(_ descriptor: ModelDescriptor) {}

    func preparedDescriptors() -> [ModelDescriptor] { [] }
}

private actor StubTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()
    func prepare() async throws {}
    func releaseIdleResources() async {}
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        _ = languageHint
        return TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
    }
    func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
    }
}

private actor StubStreamingTranscriber: StreamingTranscriber {
    nonisolated let capabilities = TranscriberCapabilities()
    func prepare() async throws {}
    func releaseIdleResources() async {}
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor SharedWhisperCppAdapter: Transcriber, StreamingTranscriber {
    nonisolated let capabilities = TranscriberCapabilities()

    func prepare() async throws {}
    func releaseIdleResources() async {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }

    func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        _ = languageHint
        return TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
    }

    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async throws -> TranscriptionResult {
        _ = stream
        return TranscriptionResult(
            text: "",
            audioDuration: .zero,
            processingDuration: .zero
        )
    }

    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        _ = stream
        return AsyncThrowingStream { $0.finish() }
    }
}

private actor StubDiarizer: SpeakerDiarizer {
    func prepare() async throws {}
    func releaseIdleResources() async {}
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    nonisolated func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { $0.finish() }
    }
}
