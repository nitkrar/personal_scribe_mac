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
            // The protocol-based `StubModelService` was dropped in
            // #024.10 along with the `ModelService` protocol itself.
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
                download: { _, _ in }
            )
        }
        let coordinator = SessionCoordinator(
            capture: FakeAudioCapturer(buffers: [buffer]),
            modelService: modelService,
            transcriberProvider: StubModelBoundTranscriberProvider(
                transcribersByID: [
                    firstDescriptor.id: firstTranscriber,
                    secondDescriptor.id: secondTranscriber,
                ]
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.session)
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

        let firstStates = try await withTimeout(.seconds(1)) {
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

        XCTAssertEqual(firstStates, [.idle, .recording, .transcribing, .idle])
        XCTAssertEqual(firstPrepareCount, 1)
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

        let secondStates = try await withTimeout(.seconds(1)) {
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

        XCTAssertEqual(secondStates, [.idle, .recording, .transcribing, .idle])
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

private struct StubModelBoundTranscriberProvider: ModelBoundTranscriberProviding {
    let transcribersByID: [String: any Transcribing]

    func transcriber(for descriptor: ModelDescriptor) -> any Transcribing {
        transcribersByID[descriptor.id] ?? transcribersByID[BuiltInModelCatalog.parakeetTDT06Bv2.id]!
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
