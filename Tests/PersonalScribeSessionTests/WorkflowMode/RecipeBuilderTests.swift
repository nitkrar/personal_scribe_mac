import XCTest
import PersonalScribeCore
@testable import PersonalScribeSession

@MainActor
final class RecipeBuilderTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

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
        let mode = RecipeWorkflowMode(
            id: "vad-mode",
            name: "VAD Mode",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [
                .vad(
                    silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                    showWarning: .override(true),
                    showAutoStoppedNotification: .setting(
                        PreferenceKeys.vadShowAutoStoppedNotification
                    )
                ),
                .manualHotkey,
            ],
            outputSinks: [.frontmostPaste]
        )

        let bound = try builder.build(mode)

        guard case .vad(let silenceThreshold, let showWarning, let showAutoStopped) = bound.captureControllers[0] else {
            XCTFail("Expected .vad first capture controller, got \(bound.captureControllers)")
            return
        }
        XCTAssertEqual(silenceThreshold, 2.5)
        XCTAssertTrue(showWarning)
        XCTAssertFalse(showAutoStopped) // setting key default: false
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
        service.setActive(BuiltInModelCatalog.parakeetTDTCTC110M)

        // The bound recipe still references the original descriptor.
        XCTAssertEqual(provider.transcriberRequests.map(\.id), [BuiltInModelCatalog.parakeetTDT06Bv2.id])
        XCTAssertEqual(bound.processors.count, 1)
    }

    // MARK: - Helpers

    private func makeServiceWithActive(asr asrID: String?) -> ActiveModelService {
        let preference = Preference<[ModelKind: String]>(
            key: "RecipeBuilderTests-\(suiteName ?? "ActiveIDs")",
            default: [:],
            defaults: defaults
        )
        if let asrID {
            preference.persist([.asr: asrID])
        }
        return ActiveModelService(
            activeIDsPreference: preference,
            isDownloaded: { _ in true },
            download: { _, _ in }
        )
    }
}

/// In-memory stub of `ModelBoundProcessorProviding` that records the
/// descriptors passed to each accessor.
private final class StubProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var transcribers: [String: any Transcriber2] = [:]
    private(set) var transcriberRequests: [ModelDescriptor] = []

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber2 {
        lock.withLock {
            transcriberRequests.append(descriptor)
            if let existing = transcribers[descriptor.id] {
                return existing
            }
            let new = StubTranscriber()
            transcribers[descriptor.id] = new
            return new
        }
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        StubStreamingTranscriber()
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
}

private actor StubTranscriber: Transcriber2 {
    nonisolated let capabilities = TranscriberCapabilities()
    func prepare() async throws {}
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
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
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { $0.finish() }
    }
}

private actor StubDiarizer: SpeakerDiarizer {
    func prepare() async throws {}
    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { $0.finish() }
    }
    nonisolated func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { $0.finish() }
    }
}
