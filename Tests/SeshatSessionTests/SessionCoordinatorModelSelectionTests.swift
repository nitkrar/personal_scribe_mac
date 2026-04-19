import Combine
import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

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
            StubModelService(
                activeDescriptor: ActiveModelDescriptor(voiceModel: firstDescriptor)
            )
        }
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturing(buffers: [buffer]),
            modelService: modelService,
            transcriberProvider: StubModelBoundTranscriberProvider(
                transcribersByID: [
                    firstDescriptor.id: firstTranscriber,
                    secondDescriptor.id: secondTranscriber,
                ]
            ),
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let stream = await coordinator.stateStream()
        let observedStates = Task { () -> [SessionState] in
            var observed: [SessionState] = []
            for await state in stream.prefix(7) {
                observed.append(state)
            }
            return observed
        }

        await coordinator.toggle()
        try await modelService.setActiveVoiceModel(secondDescriptor.id)
        await coordinator.toggle()

        let firstPrepareCount = await firstTranscriber.prepareCallCount
        let firstTranscribeCount = await firstTranscriber.transcribeCallCount
        let secondPrepareCountAfterFirstSession = await secondTranscriber.prepareCallCount
        let secondTranscribeCountAfterFirstSession = await secondTranscriber.transcribeCallCount
        let firstResultText = await coordinator.lastResult()?.text

        XCTAssertEqual(firstPrepareCount, 1)
        XCTAssertEqual(firstTranscribeCount, 1)
        XCTAssertEqual(secondPrepareCountAfterFirstSession, 0)
        XCTAssertEqual(secondTranscribeCountAfterFirstSession, 0)
        XCTAssertEqual(firstResultText, "First model.")

        await coordinator.toggle()
        await coordinator.toggle()

        let states = try await withTimeout(.seconds(1)) {
            await observedStates.value
        }
        let secondPrepareCount = await secondTranscriber.prepareCallCount
        let secondTranscribeCount = await secondTranscriber.transcribeCallCount
        let secondResultText = await coordinator.lastResult()?.text

        XCTAssertEqual(states, [.idle, .recording, .transcribing, .idle, .recording, .transcribing, .idle])
        XCTAssertEqual(secondPrepareCount, 1)
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

@MainActor
private final class StubModelService: ModelService {
    let registeredModels: [ModelDescriptor]
    @Published private(set) var activeDescriptor: ActiveModelDescriptor

    init(
        registeredModels: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        activeDescriptor: ActiveModelDescriptor
    ) {
        self.registeredModels = registeredModels
        self.activeDescriptor = activeDescriptor
    }

    func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor {
        let voiceModel = registeredModels.first { $0.id == mode.voiceModelID }
            ?? BuiltInModelCatalog.defaultActiveDescriptor.voiceModel
        return ActiveModelDescriptor(voiceModel: voiceModel, aiModelID: mode.aiModelID)
    }

    func setActive(_ descriptor: ActiveModelDescriptor) async throws {
        guard let canonical = registeredModels.first(where: { $0.id == descriptor.voiceModel.id }) else {
            throw ModelSelectionError.unknownVoiceModelID(descriptor.voiceModel.id)
        }

        activeDescriptor = ActiveModelDescriptor(
            voiceModel: canonical,
            aiModelID: descriptor.aiModelID
        )
    }

    func setActiveVoiceModel(_ id: String) async throws {
        guard let voiceModel = registeredModels.first(where: { $0.id == id }) else {
            throw ModelSelectionError.unknownVoiceModelID(id)
        }

        activeDescriptor = ActiveModelDescriptor(
            voiceModel: voiceModel,
            aiModelID: activeDescriptor.aiModelID
        )
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        true
    }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        progress(.init(phase: .finished, fractionCompleted: 1, receivedBytes: 0, expectedBytes: nil))
    }
}

private struct StubModelBoundTranscriberProvider: ModelBoundTranscriberProviding {
    let transcribersByID: [String: any Transcribing]

    func transcriber(for descriptor: ModelDescriptor) -> any Transcribing {
        transcribersByID[descriptor.id] ?? transcribersByID[BuiltInModelCatalog.defaultActiveDescriptor.voiceModel.id]!
    }
}

private actor RecordingTranscriber: Transcribing {
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

    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) async throws -> TranscriptionResult {
        for try await _ in stream {}
        transcribeCallCount += 1
        return result
    }
}
