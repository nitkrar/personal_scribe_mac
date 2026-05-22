import Foundation
import XCTest
import PersonalScribeCore
import PersonalScribeTestSupport
@testable import PersonalScribeSession

final class SessionCoordinatorGracefulShutdownTests: XCTestCase {
    func testShutdownWaitsForTranscribingToSettleBeforeEvictingPreparedWhisperCppAdapters() async throws {
        let activeDescriptor = BuiltInModelCatalog.whisperCppTiny
        let extraPreparedWhisper = BuiltInModelCatalog.whisperCppSmallQ51
        let unpreparedWhisper = BuiltInModelCatalog.whisperCppLargeV3TurboQ50
        let preparedWhisperKit = BuiltInModelCatalog.whisperKitTiny
        let transcriber = FakeTranscriber(
            result: makeResult(text: "Whisper"),
            delay: .milliseconds(200)
        )
        let provider = TrackingModelBoundProcessorProvider(
            transcribersByID: [
                activeDescriptor.id: transcriber,
                extraPreparedWhisper.id: FakeTranscriber(result: makeResult(text: "Extra")),
                preparedWhisperKit.id: FakeTranscriber(result: makeResult(text: "Kit")),
            ],
            cachedDescriptorIDs: [
                extraPreparedWhisper.id,
                preparedWhisperKit.id,
            ]
        )
        let coordinator = try await makeCoordinator(
            activeDescriptor: activeDescriptor,
            registeredModels: [
                activeDescriptor,
                extraPreparedWhisper,
                unpreparedWhisper,
                preparedWhisperKit,
            ],
            provider: provider,
            capture: FakeAudioCapturer(buffers: [try makeBuffer()])
        )

        await coordinator.startIfIdle()
        try await waitUntilDisplayState(.capturing, coordinator: coordinator)
        let stopTask = Task {
            await coordinator.stopIfActive()
        }
        try await waitUntilRawState(.transcribing, coordinator: coordinator)

        let shutdownTask = Task {
            await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination(
                waitTimeout: .seconds(1)
            )
        }

        try await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(
            provider.evictionRequests,
            [],
            "Shutdown should not evict whisper.cpp adapters while the coordinator is still transcribing."
        )

        await stopTask.value
        await shutdownTask.value

        let settledState = await coordinator.state()
        XCTAssertEqual(settledState, .idle)
        XCTAssertEqual(
            Set(provider.evictionRequests),
            Set([activeDescriptor.id, extraPreparedWhisper.id])
        )
        XCTAssertFalse(provider.evictionRequests.contains(unpreparedWhisper.id))
        XCTAssertFalse(provider.evictionRequests.contains(preparedWhisperKit.id))
    }

    func testShutdownTimesOutAndEvictsPreparedWhisperCppAdaptersWhenSessionStaysBusy() async throws {
        let activeDescriptor = BuiltInModelCatalog.whisperCppTiny
        let extraPreparedWhisper = BuiltInModelCatalog.whisperCppLargeV3TurboQ50
        let transcriber = FakeTranscriber(
            result: makeResult(text: "Whisper"),
            delay: .seconds(1)
        )
        let provider = TrackingModelBoundProcessorProvider(
            transcribersByID: [
                activeDescriptor.id: transcriber,
                extraPreparedWhisper.id: FakeTranscriber(result: makeResult(text: "Extra")),
            ],
            cachedDescriptorIDs: [extraPreparedWhisper.id]
        )
        let coordinator = try await makeCoordinator(
            activeDescriptor: activeDescriptor,
            registeredModels: [
                activeDescriptor,
                extraPreparedWhisper,
            ],
            provider: provider,
            capture: FakeAudioCapturer(buffers: [try makeBuffer()])
        )

        await coordinator.startIfIdle()
        try await waitUntilDisplayState(.capturing, coordinator: coordinator)
        let stopTask = Task {
            await coordinator.stopIfActive()
        }
        try await waitUntilRawState(.transcribing, coordinator: coordinator)

        let startedAt = ContinuousClock.now

        await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination(
            waitTimeout: .milliseconds(100)
        )

        let elapsed = startedAt.duration(to: ContinuousClock.now)

        let stateAfterTimeout = await coordinator.state()
        XCTAssertEqual(stateAfterTimeout, .transcribing)
        XCTAssertGreaterThanOrEqual(elapsed, .milliseconds(100))
        XCTAssertLessThan(elapsed, .milliseconds(500))
        XCTAssertEqual(
            Set(provider.evictionRequests),
            Set([activeDescriptor.id, extraPreparedWhisper.id])
        )

        await stopTask.value
    }

    func testShutdownSkipsEvictionWhenNoWhisperCppAdaptersArePrepared() async throws {
        let activeDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let provider = TrackingModelBoundProcessorProvider(
            transcribersByID: [
                activeDescriptor.id: FakeTranscriber(result: makeResult(text: "Parakeet")),
            ],
            cachedDescriptorIDs: [activeDescriptor.id]
        )
        let coordinator = try await makeCoordinator(
            activeDescriptor: activeDescriptor,
            registeredModels: [activeDescriptor, BuiltInModelCatalog.whisperCppTiny],
            provider: provider
        )

        await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination(
            waitTimeout: .milliseconds(50)
        )

        XCTAssertEqual(provider.evictionRequests, [])
    }

    func testShutdownEvictsActiveWhisperCppDescriptorEvenWhenItIsNotPrepared() async throws {
        let activeDescriptor = BuiltInModelCatalog.whisperCppTiny
        let extraWhisper = BuiltInModelCatalog.whisperCppSmallQ51
        let provider = TrackingModelBoundProcessorProvider(
            transcribersByID: [
                activeDescriptor.id: FakeTranscriber(result: makeResult(text: "Whisper")),
                extraWhisper.id: FakeTranscriber(result: makeResult(text: "Extra")),
            ]
        )
        let coordinator = try await makeCoordinator(
            activeDescriptor: activeDescriptor,
            registeredModels: [activeDescriptor, extraWhisper],
            provider: provider
        )

        await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination(
            waitTimeout: .milliseconds(50)
        )

        XCTAssertEqual(provider.evictionRequests, [activeDescriptor.id])
    }

    func testShutdownHonorsCancellationBeforeEvictingPreparedWhisperCppAdapters() async throws {
        let activeDescriptor = BuiltInModelCatalog.whisperCppTiny
        let extraPreparedWhisper = BuiltInModelCatalog.whisperCppSmallQ51
        let transcriber = FakeTranscriber(
            result: makeResult(text: "Whisper"),
            delay: .seconds(1)
        )
        let provider = TrackingModelBoundProcessorProvider(
            transcribersByID: [
                activeDescriptor.id: transcriber,
                extraPreparedWhisper.id: FakeTranscriber(result: makeResult(text: "Extra")),
            ],
            cachedDescriptorIDs: [extraPreparedWhisper.id]
        )
        let coordinator = try await makeCoordinator(
            activeDescriptor: activeDescriptor,
            registeredModels: [
                activeDescriptor,
                extraPreparedWhisper,
            ],
            provider: provider,
            capture: FakeAudioCapturer(buffers: [try makeBuffer()])
        )

        await coordinator.startIfIdle()
        try await waitUntilDisplayState(.capturing, coordinator: coordinator)
        let stopTask = Task {
            await coordinator.stopIfActive()
        }
        try await waitUntilRawState(.transcribing, coordinator: coordinator)

        let shutdownTask = Task {
            await coordinator.shutdownPreparedWhisperCppAdaptersForApplicationTermination(
                waitTimeout: .seconds(2)
            )
        }

        try await Task.sleep(for: .milliseconds(50))
        shutdownTask.cancel()
        await shutdownTask.value

        XCTAssertEqual(provider.evictionRequests, [])

        await stopTask.value
    }

    private func makeCoordinator(
        activeDescriptor: ModelDescriptor,
        registeredModels: [ModelDescriptor],
        provider: TrackingModelBoundProcessorProvider,
        capture: any AudioCapturer = FakeAudioCapturer()
    ) async throws -> SessionCoordinator {
        let modelService = await MainActor.run {
            let suiteName = "PersonalScribeTests.SessionCoordinatorGracefulShutdown.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            let preference = Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [.asr: activeDescriptor.id],
                defaults: defaults
            )
            preference.persist([.asr: activeDescriptor.id])
            return ActiveModelService(
                activeIDsPreference: preference,
                registeredModels: registeredModels,
                isDownloaded: { _ in true },
                download: { _, _ in },
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
            )
        }
        let registry = try WorkflowModeRegistry(
            store: InMemoryWorkflowModeStore(),
            availableKindsProvider: { Set(ModelKind.allCases.filter(\.isEnabled)) }
        )

        return SessionCoordinator(
            capture: capture,
            modelService: modelService,
            processorProvider: provider,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session),
            workflowModeRegistry: registry,
            availableKindsProvider: { Set(ModelKind.allCases.filter(\.isEnabled)) }
        )
    }

    private func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
    }

    private func makeResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(100)
        )
    }

    private func waitUntilRawState(
        _ expected: SessionState,
        coordinator: SessionCoordinator
    ) async throws {
        do {
            try await withTimeout(.seconds(1)) {
                while await coordinator.snapshot().sessionState != expected {
                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
        } catch is TimeoutError {
            let displayState = await coordinator.state()
            let rawState = await coordinator.snapshot().sessionState
            throw WaitTimeoutError(
                expectedState: expected,
                observedDisplayState: displayState,
                observedRawState: rawState
            )
        }
    }

    private func waitUntilDisplayState(
        _ expected: SessionState,
        coordinator: SessionCoordinator
    ) async throws {
        do {
            try await withTimeout(.seconds(1)) {
                while true {
                    let displayState = await coordinator.state()
                    if displayState == expected {
                        return
                    }

                    let rawState = await coordinator.snapshot().sessionState
                    if case .error = rawState {
                        throw UnexpectedStateError(state: rawState)
                    }

                    try Task.checkCancellation()
                    try await Task.sleep(for: .milliseconds(10))
                }
            }
        } catch is TimeoutError {
            let displayState = await coordinator.state()
            let rawState = await coordinator.snapshot().sessionState
            throw WaitTimeoutError(
                expectedState: expected,
                observedDisplayState: displayState,
                observedRawState: rawState
            )
        }
    }

    private func withTimeout<T: Sendable>(
        _ duration: Duration,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
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

    private struct UnexpectedStateError: Error {
        let state: SessionState
    }

    private struct WaitTimeoutError: Error, CustomStringConvertible {
        let expectedState: SessionState
        let observedDisplayState: SessionState
        let observedRawState: SessionState

        var description: String {
            "Timed out waiting for \(expectedState); display=\(observedDisplayState), raw=\(observedRawState)"
        }
    }
}

private final class TrackingModelBoundProcessorProvider: @unchecked Sendable, ModelBoundProcessorProviding {
    private let transcribersByID: [String: any Transcriber]
    private let lock = NSLock()
    private var cachedDescriptorIDs: Set<String>
    private var recordedEvictionRequests: [String] = []

    init(
        transcribersByID: [String: any Transcriber],
        cachedDescriptorIDs: Set<String> = []
    ) {
        self.transcribersByID = transcribersByID
        self.cachedDescriptorIDs = cachedDescriptorIDs
    }

    var evictionRequests: [String] {
        lock.withLock {
            recordedEvictionRequests
        }
    }

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber {
        guard let transcriber = transcribersByID[descriptor.id] else {
            throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
        }

        _ = lock.withLock {
            cachedDescriptorIDs.insert(descriptor.id)
        }

        return transcriber
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        throw ModelSelectionError.unsupportedKind(expected: .streamingASR, actual: descriptor.engine.kind)
    }

    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        throw ModelSelectionError.unsupportedKind(expected: .diarization, actual: descriptor.engine.kind)
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        true
    }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {}

    func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {}

    func evict(_ descriptor: ModelDescriptor) {
        lock.withLock {
            recordedEvictionRequests.append(descriptor.id)
            cachedDescriptorIDs.remove(descriptor.id)
        }
    }

    func preparedDescriptors() -> [ModelDescriptor] {
        let preparedIDs = lock.withLock {
            Array(cachedDescriptorIDs)
        }
        let descriptorsByID = Dictionary(
            uniqueKeysWithValues: BuiltInModelCatalog.registeredModels.map { ($0.id, $0) }
        )
        return preparedIDs.compactMap { descriptorsByID[$0] }
    }
}
