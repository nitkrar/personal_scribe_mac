import Foundation
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

final class OfflineTranscriptionCoordinatorTests: XCTestCase {
    func testEnqueueFileTransitionsToInFlightThenCompleted() async throws {
        let harness = try makeHarness(initialSessionState: .capturing)
        defer { cleanup(harness.baseDirectory) }

        let url = harness.baseDirectory.appendingPathComponent("drop.wav", isDirectory: false)
        try Data().write(to: url)

        let snapshotsTask = Task { () -> [OfflineTranscriptionCoordinator.JobStatus] in
            let stream = await harness.coordinator.snapshotStream()
            var statuses: [OfflineTranscriptionCoordinator.JobStatus] = []
            for await snapshot in stream {
                guard let job = snapshot.first else {
                    continue
                }
                statuses.append(job.status)
                if case .completed = job.status {
                    break
                }
            }
            return statuses
        }

        let jobID = await harness.coordinator.enqueueFile(
            url: url,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )
        await harness.sessionGate.setState(.idle)
        try await waitUntil(description: "job completed") {
            guard let status = await jobStatus(for: jobID, coordinator: harness.coordinator) else {
                return false
            }
            if case .completed = status {
                return true
            }
            return false
        }

        let observedStatuses = await snapshotsTask.value
        XCTAssertTrue(observedStatuses.contains(.queued))
        XCTAssertTrue(observedStatuses.contains { status in
            if case .inFlight = status {
                return true
            }
            return false
        })
        XCTAssertTrue(observedStatuses.contains { status in
            if case .completed = status {
                return true
            }
            return false
        })

        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].text, "Hello world.")
        XCTAssertEqual(entries[0].audioFilename, url.path)
    }

    func testReTranscribeWithFixedDictationRecipeWritesNewDBRow() async throws {
        let harness = try makeHarness(initialSessionState: .capturing, now: Date(timeIntervalSince1970: 1234))
        defer { cleanup(harness.baseDirectory) }

        let sourceFilename = "recording.wav"
        let sourceURL = harness.recordingsDirectory.appendingPathComponent(sourceFilename, isDirectory: false)
        try Data().write(to: sourceURL)

        let originalEntry = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "original",
            audioFilename: sourceFilename
        )
        try await harness.repository.append(originalEntry)

        let jobID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)
        await harness.sessionGate.setState(.idle)

        try await waitUntil(description: "re-transcribe completed") {
            guard let status = await jobStatus(for: jobID, coordinator: harness.coordinator) else {
                return false
            }
            if case .completed = status {
                return true
            }
            return false
        }

        let jobs = await harness.coordinator.snapshot()
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].recipeOverride, .fixedDictation)
        XCTAssertFalse(jobs[0].diarize)
        XCTAssertEqual(jobs[0].sourceFilename, sourceFilename)

        let entries = await harness.repository.all().sorted { $0.timestamp < $1.timestamp }
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].id, originalEntry.id)
        let newEntry = try XCTUnwrap(entries.first { $0.id != originalEntry.id })
        XCTAssertEqual(newEntry.text, "Hello world.")
        XCTAssertEqual(newEntry.timestamp, Date(timeIntervalSince1970: 1234))
        XCTAssertEqual(newEntry.audioFilename, sourceFilename)
        XCTAssertNil(newEntry.modeId)
    }

    func testReTranscribeForMissingFileFailsFastAndNullsColumn() async throws {
        let harness = try makeHarness(initialSessionState: .idle)
        defer { cleanup(harness.baseDirectory) }

        let sourceFilename = "missing.wav"
        let originalEntry = makeEntry(
            timestamp: Date(timeIntervalSince1970: 100),
            text: "original",
            audioFilename: sourceFilename
        )
        try await harness.repository.append(originalEntry)

        let jobID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)

        let status = try await waitForStatus(jobID, coordinator: harness.coordinator) { status in
            status == .failed(reason: .audioMissing)
        }
        XCTAssertEqual(status, .failed(reason: .audioMissing))

        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertNil(entries[0].audioFilename)
    }

    func testMultipleEnqueuesProcessSerially() async throws {
        let transcriber = RecordingTranscriber(
            outcomes: [
                .success(makeResult(text: "first")),
                .success(makeResult(text: "second")),
            ],
            delay: .milliseconds(100)
        )
        let harness = try makeHarness(
            initialSessionState: .capturing,
            transcribersByID: [BuiltInModelCatalog.parakeetTDT06Bv2.id: transcriber]
        )
        defer { cleanup(harness.baseDirectory) }

        let firstURL = harness.baseDirectory.appendingPathComponent("one.wav", isDirectory: false)
        let secondURL = harness.baseDirectory.appendingPathComponent("two.wav", isDirectory: false)
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let firstID = await harness.coordinator.enqueueFile(
            url: firstURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )
        let secondID = await harness.coordinator.enqueueFile(
            url: secondURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )

        await harness.sessionGate.setState(.idle)
        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }
        _ = try await waitForStatus(secondID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }

        let maxConcurrent = await transcriber.maxConcurrentTranscribes()
        XCTAssertEqual(maxConcurrent, 1)
        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 2)
    }

    func testCancelInFlightTransitionsToCancelledAndPicksUpNext() async throws {
        let transcriber = RecordingTranscriber(
            outcomes: [
                .success(makeResult(text: "first")),
                .success(makeResult(text: "second")),
            ],
            delay: .milliseconds(250)
        )
        let harness = try makeHarness(
            initialSessionState: .capturing,
            transcribersByID: [BuiltInModelCatalog.parakeetTDT06Bv2.id: transcriber]
        )
        defer { cleanup(harness.baseDirectory) }

        let firstURL = harness.baseDirectory.appendingPathComponent("first.wav", isDirectory: false)
        let secondURL = harness.baseDirectory.appendingPathComponent("second.wav", isDirectory: false)
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let firstID = await harness.coordinator.enqueueFile(
            url: firstURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )
        let secondID = await harness.coordinator.enqueueFile(
            url: secondURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )

        await harness.sessionGate.setState(.idle)
        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .inFlight = status {
                return true
            }
            return false
        }

        await harness.coordinator.cancelJob(id: firstID)

        let firstStatus = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            status == .cancelled
        }
        XCTAssertEqual(firstStatus, .cancelled)

        let secondStatus = try await waitForStatus(secondID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }
        if case .completed = secondStatus {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected second job to complete")
        }

        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 1)
        XCTAssertFalse(entries[0].text.isEmpty)
    }

    func testDequeueQueuedJobRemovesItWithoutStarting() async throws {
        let harness = try makeHarness(initialSessionState: .capturing)
        defer { cleanup(harness.baseDirectory) }

        let firstURL = harness.baseDirectory.appendingPathComponent("queued-first.wav", isDirectory: false)
        let secondURL = harness.baseDirectory.appendingPathComponent("queued-second.wav", isDirectory: false)
        try Data().write(to: firstURL)
        try Data().write(to: secondURL)

        let firstID = await harness.coordinator.enqueueFile(
            url: firstURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )
        let secondID = await harness.coordinator.enqueueFile(
            url: secondURL,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )

        await harness.coordinator.dequeueJob(id: secondID)
        await harness.sessionGate.setState(.idle)

        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }

        let jobs = await harness.coordinator.snapshot()
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].id, firstID)
        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 1)
    }

    func testLiveCaptureGateBlocksProcessingUntilSessionIdle() async throws {
        let harness = try makeHarness(initialSessionState: .capturing)
        defer { cleanup(harness.baseDirectory) }

        let url = harness.baseDirectory.appendingPathComponent("gated.wav", isDirectory: false)
        try Data().write(to: url)

        let jobID = await harness.coordinator.enqueueFile(
            url: url,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )

        try await Task.sleep(for: .milliseconds(50))
        let currentStatus = await jobStatus(for: jobID, coordinator: harness.coordinator)
        let entriesBeforeIdle = await harness.repository.all()
        XCTAssertEqual(currentStatus, .queued)
        XCTAssertTrue(entriesBeforeIdle.isEmpty)

        await harness.sessionGate.setState(.idle)

        let finalStatus = try await waitForStatus(jobID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }
        if case .completed = finalStatus {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected gated job to complete once idle")
        }
    }

    func testFailedTranscriptionMarksJobFailedWithoutDBWrite() async throws {
        let transcriber = RecordingTranscriber(
            outcomes: [.failure(.transcriptionFailure)]
        )
        let harness = try makeHarness(
            initialSessionState: .capturing,
            transcribersByID: [BuiltInModelCatalog.parakeetTDT06Bv2.id: transcriber]
        )
        defer { cleanup(harness.baseDirectory) }

        let url = harness.baseDirectory.appendingPathComponent("fail.wav", isDirectory: false)
        try Data().write(to: url)

        let jobID = await harness.coordinator.enqueueFile(
            url: url,
            descriptorID: harness.asrDescriptor.id,
            diarize: false
        )
        await harness.sessionGate.setState(.idle)

        let status = try await waitForStatus(jobID, coordinator: harness.coordinator) { status in
            status == .failed(reason: .transcriptionFailed)
        }
        XCTAssertEqual(status, .failed(reason: .transcriptionFailed))
        let entries = await harness.repository.all()
        XCTAssertTrue(entries.isEmpty)
    }

    func testReTranscribeDeduplicatesWhenJobAlreadyQueued() async throws {
        let harness = try makeHarness(initialSessionState: .capturing)
        defer { cleanup(harness.baseDirectory) }

        let sourceFilename = "queued.wav"
        let sourceURL = harness.recordingsDirectory.appendingPathComponent(sourceFilename, isDirectory: false)
        try Data().write(to: sourceURL)
        try await harness.repository.append(
            makeEntry(
                timestamp: Date(timeIntervalSince1970: 100),
                text: "original",
                audioFilename: sourceFilename
            )
        )

        let firstID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)
        let secondID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)

        XCTAssertEqual(firstID, secondID)
        let jobs = await harness.coordinator.snapshot()
        XCTAssertEqual(jobs.count, 1)
        XCTAssertEqual(jobs[0].status, .queued)
    }

    func testReTranscribeDeduplicatesWhenJobInFlight() async throws {
        let transcriber = RecordingTranscriber(
            outcomes: [.success(makeResult(text: "first"))],
            delay: .milliseconds(250)
        )
        let harness = try makeHarness(
            initialSessionState: .capturing,
            transcribersByID: [BuiltInModelCatalog.parakeetTDT06Bv2.id: transcriber]
        )
        defer { cleanup(harness.baseDirectory) }

        let sourceFilename = "inflight.wav"
        let sourceURL = harness.recordingsDirectory.appendingPathComponent(sourceFilename, isDirectory: false)
        try Data().write(to: sourceURL)
        try await harness.repository.append(
            makeEntry(
                timestamp: Date(timeIntervalSince1970: 100),
                text: "original",
                audioFilename: sourceFilename
            )
        )

        let firstID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)
        await harness.sessionGate.setState(.idle)

        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .inFlight = status {
                return true
            }
            return false
        }
        let secondID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)

        XCTAssertEqual(firstID, secondID)

        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }
        let entryCount = await harness.repository.all().count
        XCTAssertEqual(entryCount, 2)
    }

    func testReTranscribeAllowsNewJobAfterPriorCompleted() async throws {
        let transcriber = RecordingTranscriber(
            outcomes: [
                .success(makeResult(text: "first")),
                .success(makeResult(text: "second")),
            ]
        )
        let harness = try makeHarness(
            initialSessionState: .capturing,
            transcribersByID: [BuiltInModelCatalog.parakeetTDT06Bv2.id: transcriber]
        )
        defer { cleanup(harness.baseDirectory) }

        let sourceFilename = "completed.wav"
        let sourceURL = harness.recordingsDirectory.appendingPathComponent(sourceFilename, isDirectory: false)
        try Data().write(to: sourceURL)
        try await harness.repository.append(
            makeEntry(
                timestamp: Date(timeIntervalSince1970: 100),
                text: "original",
                audioFilename: sourceFilename
            )
        )

        let firstID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)
        await harness.sessionGate.setState(.idle)
        _ = try await waitForStatus(firstID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }

        let secondID = await harness.coordinator.reTranscribe(sourceFilename: sourceFilename)
        XCTAssertNotEqual(firstID, secondID)
        _ = try await waitForStatus(secondID, coordinator: harness.coordinator) { status in
            if case .completed = status {
                return true
            }
            return false
        }

        let entries = await harness.repository.all()
        XCTAssertEqual(entries.count, 3)
    }
}

private extension OfflineTranscriptionCoordinatorTests {
    struct Harness {
        let baseDirectory: URL
        let recordingsDirectory: URL
        let repository: TranscriptRepository
        let coordinator: OfflineTranscriptionCoordinator
        let sessionGate: TestSessionGate
        let asrDescriptor: ModelDescriptor
    }

    func makeHarness(
        initialSessionState: SessionState,
        transcribersByID: [String: any Transcriber]? = nil,
        diarizer: (any SpeakerDiarizer)? = nil,
        now: Date = Date(timeIntervalSince1970: 2_000)
    ) throws -> Harness {
        let baseDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OfflineTranscriptionCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        let recordingsDirectory = baseDirectory.appendingPathComponent("recordings", isDirectory: true)
        try FileManager.default.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)

        let locator = FixedBaseDirectoryStorageLocator(
            baseDirectory: baseDirectory,
            managedDirectoryOverrides: [.recordings: recordingsDirectory]
        )
        let database = try AppDatabase(locator: locator)
        let repository = TranscriptRepository(
            database: database,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        let sessionGate = TestSessionGate(initialState: initialSessionState)
        let asrDescriptor = BuiltInModelCatalog.parakeetTDT06Bv2
        let defaultTranscriber = RecordingTranscriber(outcomes: [.success(makeResult(text: "hello world"))])
        let provider = TestProcessorProvider(
            transcribersByID: transcribersByID ?? [asrDescriptor.id: defaultTranscriber],
            diarizer: diarizer
        )

        let buffer = try makeTestBuffer(sampleCount: 16_000)
        let stream = ScriptedFileSourceAudioStream { url in
            _ = url
            return AsyncThrowingStream { continuation in
                continuation.yield(buffer)
                continuation.finish()
            }
        }

        let coordinator = OfflineTranscriptionCoordinator(
            activeASRDescriptor: { asrDescriptor },
            descriptorByID: { descriptorID in
                [asrDescriptor, BuiltInModelCatalog.speakerDiarization].first { $0.id == descriptorID }
            },
            processorProvider: provider,
            transcriptRepository: repository,
            sessionGate: sessionGate,
            fileSourceAudioStream: stream,
            recordingsDirectory: { recordingsDirectory },
            now: { now },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )

        return Harness(
            baseDirectory: baseDirectory,
            recordingsDirectory: recordingsDirectory,
            repository: repository,
            coordinator: coordinator,
            sessionGate: sessionGate,
            asrDescriptor: asrDescriptor
        )
    }

    func makeResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(100)
        )
    }

    func makeEntry(
        timestamp: Date,
        text: String,
        audioFilename: String?
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: UUID(),
            timestamp: timestamp,
            text: text,
            audioDuration: 1,
            processingDuration: 0.1,
            modeId: nil,
            audioFilename: audioFilename
        )
    }

    func cleanup(_ baseDirectory: URL) {
        try? FileManager.default.removeItem(at: baseDirectory)
    }
}

private actor TestSessionGate: SessionGateProviding {
    private var currentSnapshot: SessionSnapshot
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]

    init(initialState: SessionState) {
        currentSnapshot = SessionSnapshot(sessionState: initialState)
    }

    func snapshot() -> SessionSnapshot {
        currentSnapshot
    }

    func snapshotStream() -> AsyncStream<SessionSnapshot> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(currentSnapshot)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id)
                }
            }
        }
    }

    func setState(_ state: SessionState) {
        currentSnapshot.sessionState = state
        let snapshot = currentSnapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

private struct ScriptedFileSourceAudioStream: FileSourceAudioStreaming, Sendable {
    let factory: @Sendable (URL) -> AsyncThrowingStream<PCMBuffer, Error>

    func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error> {
        factory(url)
    }
}

private struct TestProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    let transcribersByID: [String: any Transcriber]
    let diarizer: (any SpeakerDiarizer)?

    func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber {
        guard let transcriber = transcribersByID[descriptor.id] else {
            throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
        }
        return transcriber
    }

    func streamingTranscriber(for descriptor: ModelDescriptor) throws -> any StreamingTranscriber {
        throw ModelSelectionError.unsupportedKind(expected: .streamingASR, actual: descriptor.kind)
    }

    func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        guard let diarizer else {
            throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
        }
        return diarizer
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

private actor RecordingTranscriber: Transcriber {
    enum Outcome: Sendable {
        case success(TranscriptionResult)
        case failure(PersonalScribeError)
    }

    nonisolated let capabilities = TranscriberCapabilities()

    private let outcomes: [Outcome]
    private let delay: Duration?
    private var outcomeIndex = 0
    private var activeTranscribes = 0
    private var maxConcurrent = 0

    init(
        outcomes: [Outcome],
        delay: Duration? = nil
    ) {
        self.outcomes = outcomes
        self.delay = delay
    }

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.yield(
                .init(phase: .idle, fractionCompleted: 0, receivedBytes: 0, expectedBytes: nil)
            )
            continuation.finish()
        }
    }

    func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        _ = audio
        _ = languageHint
        activeTranscribes += 1
        maxConcurrent = max(maxConcurrent, activeTranscribes)
        defer {
            activeTranscribes -= 1
        }

        if let delay {
            try await Task.sleep(for: delay)
        }

        let index = min(outcomeIndex, outcomes.count - 1)
        outcomeIndex += 1
        switch outcomes[index] {
        case .success(let result):
            return result
        case .failure(let error):
            throw error
        }
    }

    func releaseIdleResources() async {}

    func maxConcurrentTranscribes() -> Int {
        maxConcurrent
    }
}

private struct WaitTimeout: Error {
    let description: String
}

private func jobStatus(
    for id: UUID,
    coordinator: OfflineTranscriptionCoordinator
) async -> OfflineTranscriptionCoordinator.JobStatus? {
    await coordinator.snapshot().first(where: { $0.id == id })?.status
}

private func waitForStatus(
    _ id: UUID,
    coordinator: OfflineTranscriptionCoordinator,
    predicate: @escaping @Sendable (OfflineTranscriptionCoordinator.JobStatus) -> Bool
) async throws -> OfflineTranscriptionCoordinator.JobStatus {
    try await waitUntil(description: "status predicate for \(id.uuidString)") {
        guard let status = await jobStatus(for: id, coordinator: coordinator) else {
            return false
        }
        return predicate(status)
    }
    let status = await jobStatus(for: id, coordinator: coordinator)
    return try XCTUnwrap(status)
}

private func waitUntil(
    description: String,
    timeout: Duration = .seconds(2),
    pollInterval: Duration = .milliseconds(10),
    condition: @escaping @Sendable () async -> Bool
) async throws {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(for: pollInterval)
    }
    XCTFail("Timed out waiting for condition: \(description)")
    throw WaitTimeout(description: description)
}

private func makeTestBuffer(sampleCount: Int) throws -> PCMBuffer {
    try PCMBuffer(
        samples: (0..<sampleCount).map { Float($0) },
        timestamp: ContinuousClock().now
    )
}
