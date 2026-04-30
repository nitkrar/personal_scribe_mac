import Combine
import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorModelSelectionTests: XCTestCase {
    func testRecordingSessionStaysPinnedWhileNextRecordingUsesUpdatedActiveModel() async throws {
        let firstDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let secondDescriptor = BuiltInModelCatalog.parakeetTDTCTC110M
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
        let firstTranscriber = RecordingTranscriber(
            result: .init(
                text: "first model",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(100)
            )
        )
        let secondTranscriber = RecordingTranscriber(
            result: .init(
                text: "second model",
                audioDuration: .seconds(1),
                processingDuration: .milliseconds(100)
            )
        )
        let modelService = await MainActor.run {
            // Real `ActiveModelService` constructed with closure
            // handlers — same pattern as `ActiveModelServiceTests`.
            let suiteName = "PersonalScribeTests.SessionCoordinatorModelSelection.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            let preference = Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: defaults
            )
            preference.persist([.asr: firstDescriptor.id])
            return ActiveModelService(
                activeIDsPreference: preference,
                isDownloaded: { _ in true },
                download: { _, _ in },
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
            )
        }
        let processorProvider = FakeModelBoundProcessorProvider(
            transcribersByID: [
                firstDescriptor.id: firstTranscriber,
                secondDescriptor.id: secondTranscriber,
            ]
        )
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases.filter(\.isEnabled)) }
        )
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            modelService: modelService,
            processorProvider: processorProvider,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            workflowModeRegistry: registry,
            availableKindsProvider: { Set(ModelKind.allCases.filter(\.isEnabled)) }
        )

        let firstSessionStream = await coordinator.stateStream()
        let firstObservedStates = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in firstSessionStream.prefix(4) {
                observed.append(state)
            }
            return observed
        }

        await coordinator.toggle()
        await MainActor.run {
            modelService.setActive(secondDescriptor)
        }
        await coordinator.toggle()

        let firstStates: [SessionState] = try await withTimeout(.seconds(1)) {
            await firstObservedStates.value
        }
        let firstPrepareCount = try await withTimeout(.seconds(1)) {
            while await firstTranscriber.prepareCallCount == 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return await firstTranscriber.prepareCallCount
        }
        let firstTranscribeCount = await firstTranscriber.transcribeCallCount
        let secondPrepareCountAfterFirstSession = await secondTranscriber.prepareCallCount
        let secondTranscribeCountAfterFirstSession = await secondTranscriber.transcribeCallCount
        let firstResultText = await coordinator.lastResult()?.text

        XCTAssertEqual(
            firstStates,
            [SessionState.idle, .capturing, .transcribing, .idle]
        )
        XCTAssertGreaterThanOrEqual(firstPrepareCount, 1)
        XCTAssertEqual(firstTranscribeCount, 1)
        XCTAssertEqual(secondPrepareCountAfterFirstSession, 0)
        XCTAssertEqual(secondTranscribeCountAfterFirstSession, 0)
        XCTAssertEqual(firstResultText, "First model.")

        let secondSessionStream = await coordinator.stateStream()
        let secondObservedStates = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in secondSessionStream.prefix(4) {
                observed.append(state)
            }
            return observed
        }

        await coordinator.toggle()
        await coordinator.toggle()

        let secondStates: [SessionState] = try await withTimeout(.seconds(1)) {
            await secondObservedStates.value
        }
        let secondPrepareCount = try await withTimeout(.seconds(1)) {
            while await secondTranscriber.prepareCallCount == 0 {
                try? await Task.sleep(for: .milliseconds(10))
            }
            return await secondTranscriber.prepareCallCount
        }
        let secondTranscribeCount = await secondTranscriber.transcribeCallCount
        let secondResultText = await coordinator.lastResult()?.text

        XCTAssertEqual(
            secondStates,
            [SessionState.idle, .capturing, .transcribing, .idle]
        )
        XCTAssertGreaterThanOrEqual(secondPrepareCount, 1)
        XCTAssertEqual(secondTranscribeCount, 1)
        XCTAssertEqual(secondResultText, "Second model.")
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                await operation()
            }
            group.addTask {
                try await Task.sleep(for: duration)
                throw TimeoutError()
            }

            let value = try await group.next()!
            group.cancelAll()
            return value
        }
    }

    private struct TimeoutError: Error {}
}

private struct FakeModelBoundProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    let transcribersByID: [String: any Transcriber]

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber {
        guard let transcriber = transcribersByID[descriptor.id] else {
            throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
        }
        return transcriber
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        throw ModelSelectionError.unsupportedKind(expected: .streamingASR, actual: descriptor.engine.kind)
    }

    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        throw ModelSelectionError.unsupportedKind(expected: .diarization, actual: descriptor.engine.kind)
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool { true }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {}

    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {}

    func evict(_ descriptor: ModelDescriptor) {}
}

private actor RecordingTranscriber: Transcriber {
    nonisolated let capabilities = TranscriberCapabilities()

    private let result: TranscriptionResult
    private(set) var prepareCallCount = 0
    private(set) var transcribeCallCount = 0

    init(result: TranscriptionResult) {
        self.result = result
    }

    func prepare() async throws {
        prepareCallCount += 1
    }

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
            )
            continuation.finish()
        }
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        transcribeCallCount += 1
        return result
    }
}
