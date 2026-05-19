import Foundation
import XCTest
@testable import PersonalScribeCore

final class OfflineTranscriptionCoordinatorTests: XCTestCase {
    private let fileManager = FileManager.default

    func testEnqueueFileTransitionsToInFlightThenCompleted() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Enqueue"
        )
        defer { cleanup(recordingsDirectory) }

        let fileURL = try makeExistingFile(
            named: "input.wav",
            in: recordingsDirectory
        )
        let result = makeResult(text: "hello world")
        let transcriber = ScriptedTranscriber(
            steps: [.delayed(.milliseconds(150), .success(result))]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(buffersByURL: [fileURL.standardizedFileURL: [makeBuffer()]])
        )

        let jobID = await coordinator.enqueueFile(
            url: fileURL,
            descriptorID: "batch",
            diarize: false
        )

        let inFlightJob = try await waitForJob(id: jobID, in: coordinator) { job in
            if case .inFlight = job.status {
                return true
            }
            return false
        }
        if case .inFlight(let progress) = inFlightJob.status {
            XCTAssertGreaterThanOrEqual(progress, 0)
        } else {
            XCTFail("Expected in-flight status, got \(inFlightJob.status)")
        }

        let completedJob = try await waitForJob(id: jobID, in: coordinator) { job in
            if case .completed = job.status {
                return true
            }
            return false
        }
        let appendedEntries = await repository.appendedEntries()

        guard case .completed(let transcriptID) = completedJob.status else {
            return XCTFail("Expected completed status, got \(completedJob.status)")
        }
        XCTAssertEqual(appendedEntries.count, 1)
        XCTAssertEqual(appendedEntries.first?.id, transcriptID)
        XCTAssertEqual(appendedEntries.first?.text, "hello world")
    }

    func testReTranscribeWithFixedDictationRecipeWritesNewDBRow() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-ReTranscribe"
        )
        defer { cleanup(recordingsDirectory) }

        _ = try makeExistingFile(
            named: "recording.wav",
            in: recordingsDirectory
        )
        let fixedNow = Date(timeIntervalSince1970: 1_700_000_123)
        let transcriber = ScriptedTranscriber(
            steps: [.immediate(.success(makeResult(text: "retranscribed text")))]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["active-batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "active-batch" },
            recordingsDirectory: { recordingsDirectory },
            now: { fixedNow },
            fileSource: TestFileSource(
                buffersByURL: [
                    recordingsDirectory
                        .appendingPathComponent("recording.wav", isDirectory: false)
                        .standardizedFileURL: [makeBuffer()]
                ]
            )
        )

        let jobID = await coordinator.reTranscribe(sourceFilename: "recording.wav")
        let completedJob = try await waitForJob(id: jobID, in: coordinator) { job in
            if case .completed = job.status {
                return true
            }
            return false
        }
        let requestedDescriptorIDs = await runtime.requestedDescriptorIDs()
        let appendedEntries = await repository.appendedEntries()

        XCTAssertEqual(requestedDescriptorIDs, ["active-batch"])
        XCTAssertEqual(appendedEntries.count, 1)
        XCTAssertEqual(appendedEntries[0].timestamp, fixedNow)
        XCTAssertEqual(appendedEntries[0].text, "retranscribed text")
        XCTAssertEqual(appendedEntries[0].audioFilename, "recording.wav")
        XCTAssertNil(appendedEntries[0].modeId)
        guard case .completed(let transcriptID) = completedJob.status else {
            return XCTFail("Expected completed status, got \(completedJob.status)")
        }
        XCTAssertEqual(appendedEntries[0].id, transcriptID)
    }

    func testReTranscribeForMissingFileFailsFastAndNullsColumn() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Missing"
        )
        defer { cleanup(recordingsDirectory) }

        let runtime = OfflineRuntimeSpy(transcribers: ["active-batch": ScriptedTranscriber()])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "active-batch" },
            recordingsDirectory: { recordingsDirectory }
        )

        let jobID = await coordinator.reTranscribe(sourceFilename: "missing.wav")
        let failedJob = try await waitForJob(id: jobID, in: coordinator) { job in
            job.status == OfflineTranscriptionCoordinator.JobStatus.failed(
                reason: .audioMissing
            )
        }
        let nullified = try await waitForValue(timeout: .seconds(1)) {
            let calls = await repository.nullifiedFilenames()
            return calls.isEmpty ? nil : calls
        }
        let appendedEntries = await repository.appendedEntries()

        XCTAssertEqual(
            failedJob.status,
            OfflineTranscriptionCoordinator.JobStatus.failed(reason: .audioMissing)
        )
        XCTAssertEqual(nullified, [["missing.wav"]])
        XCTAssertTrue(appendedEntries.isEmpty)
    }

    func testMultipleEnqueuesProcessSerially() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Serial"
        )
        defer { cleanup(recordingsDirectory) }

        let firstURL = try makeExistingFile(named: "first.wav", in: recordingsDirectory)
        let secondURL = try makeExistingFile(named: "second.wav", in: recordingsDirectory)
        let thirdURL = try makeExistingFile(named: "third.wav", in: recordingsDirectory)
        let transcriber = ScriptedTranscriber(
            steps: [
                .delayed(.milliseconds(120), .success(makeResult(text: "one"))),
                .delayed(.milliseconds(120), .success(makeResult(text: "two"))),
                .delayed(.milliseconds(120), .success(makeResult(text: "three"))),
            ]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(
                buffersByURL: [
                    firstURL.standardizedFileURL: [makeBuffer()],
                    secondURL.standardizedFileURL: [makeBuffer()],
                    thirdURL.standardizedFileURL: [makeBuffer()],
                ]
            )
        )

        _ = await coordinator.enqueueFile(url: firstURL, descriptorID: "batch", diarize: false)
        _ = await coordinator.enqueueFile(url: secondURL, descriptorID: "batch", diarize: false)
        _ = await coordinator.enqueueFile(url: thirdURL, descriptorID: "batch", diarize: false)

        let observation = try await observeSnapshots(
            from: coordinator,
            until: { jobs in
                jobs.filter { $0.status.isTerminal }.count == 3
            }
        )
        let appendedEntries = await repository.appendedEntries()

        XCTAssertEqual(observation.maxInFlightCount, 1)
        XCTAssertEqual(appendedEntries.map(\.text), ["one", "two", "three"])
    }

    func testCancelInFlightTransitionsToCancelledAndPicksUpNext() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Cancel"
        )
        defer { cleanup(recordingsDirectory) }

        let firstURL = try makeExistingFile(named: "first.wav", in: recordingsDirectory)
        let secondURL = try makeExistingFile(named: "second.wav", in: recordingsDirectory)
        let transcriber = ScriptedTranscriber(
            steps: [
                .delayed(.seconds(10), .success(makeResult(text: "never written"))),
                .immediate(.success(makeResult(text: "second result"))),
            ]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(
                buffersByURL: [
                    firstURL.standardizedFileURL: [makeBuffer()],
                    secondURL.standardizedFileURL: [makeBuffer()],
                ]
            )
        )

        let firstID = await coordinator.enqueueFile(url: firstURL, descriptorID: "batch", diarize: false)
        let secondID = await coordinator.enqueueFile(url: secondURL, descriptorID: "batch", diarize: false)
        _ = try await waitForJob(id: firstID, in: coordinator) { job in
            if case .inFlight = job.status {
                return true
            }
            return false
        }

        await coordinator.cancelJob(id: firstID)

        let cancelledJob = try await waitForJob(id: firstID, in: coordinator) { job in
            job.status == OfflineTranscriptionCoordinator.JobStatus.cancelled
        }
        let completedSecondJob = try await waitForJob(id: secondID, in: coordinator) { job in
            if case .completed = job.status {
                return true
            }
            return false
        }
        let appendedEntries = await repository.appendedEntries()

        XCTAssertEqual(
            cancelledJob.status,
            OfflineTranscriptionCoordinator.JobStatus.cancelled
        )
        XCTAssertEqual(appendedEntries.count, 1)
        XCTAssertEqual(appendedEntries.first?.text, "second result")
        if case .completed(let transcriptID) = completedSecondJob.status {
            XCTAssertEqual(appendedEntries.first?.id, transcriptID)
        } else {
            XCTFail("Expected second job to complete, got \(completedSecondJob.status)")
        }
    }

    func testDequeueQueuedJobRemovesItWithoutStarting() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Dequeue"
        )
        defer { cleanup(recordingsDirectory) }

        let firstURL = try makeExistingFile(named: "first.wav", in: recordingsDirectory)
        let secondURL = try makeExistingFile(named: "second.wav", in: recordingsDirectory)
        let transcriber = ScriptedTranscriber(
            steps: [
                .delayed(.milliseconds(150), .success(makeResult(text: "first result"))),
                .immediate(.success(makeResult(text: "second result"))),
            ]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(
                buffersByURL: [
                    firstURL.standardizedFileURL: [makeBuffer()],
                    secondURL.standardizedFileURL: [makeBuffer()],
                ]
            )
        )

        let firstID = await coordinator.enqueueFile(url: firstURL, descriptorID: "batch", diarize: false)
        let secondID = await coordinator.enqueueFile(url: secondURL, descriptorID: "batch", diarize: false)
        _ = try await waitForJob(id: firstID, in: coordinator) { job in
            if case .inFlight = job.status {
                return true
            }
            return false
        }

        await coordinator.dequeueJob(id: secondID)

        _ = try await waitForJob(id: firstID, in: coordinator) { job in
            if case .completed = job.status {
                return true
            }
            return false
        }
        try await Task.sleep(for: .milliseconds(50))

        let snapshot = await coordinator.snapshot()
        let appendedEntries = await repository.appendedEntries()
        let requestedDescriptorIDs = await runtime.requestedDescriptorIDs()

        XCTAssertNil(snapshot.first(where: { $0.id == secondID }))
        XCTAssertEqual(appendedEntries.map(\.text), ["first result"])
        XCTAssertEqual(requestedDescriptorIDs, ["batch"])
    }

    func testLiveCaptureGateBlocksProcessingUntilSessionIdle() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Gate"
        )
        defer { cleanup(recordingsDirectory) }

        let fileURL = try makeExistingFile(named: "blocked.wav", in: recordingsDirectory)
        let gate = SessionGateSpy(initialState: .capturing)
        let runtime = OfflineRuntimeSpy(
            transcribers: [
                "batch": ScriptedTranscriber(
                    steps: [.immediate(.success(makeResult(text: "gate opened")))]
                )
            ]
        )
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: gate,
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(buffersByURL: [fileURL.standardizedFileURL: [makeBuffer()]])
        )

        let jobID = await coordinator.enqueueFile(url: fileURL, descriptorID: "batch", diarize: false)
        try await Task.sleep(for: .milliseconds(100))

        let queuedSnapshot = await coordinator.snapshot()
        let queuedEntries = await repository.appendedEntries()
        XCTAssertEqual(
            queuedSnapshot.first(where: { $0.id == jobID })?.status,
            OfflineTranscriptionCoordinator.JobStatus.queued
        )
        XCTAssertTrue(queuedEntries.isEmpty)

        await gate.setState(.idle)

        let completedJob = try await waitForJob(id: jobID, in: coordinator) { job in
            if case .completed = job.status {
                return true
            }
            return false
        }
        let completedEntries = await repository.appendedEntries()
        XCTAssertEqual(completedEntries.count, 1)
        if case .completed = completedJob.status {
            XCTAssertTrue(true)
        } else {
            XCTFail("Expected completed status after gate opened")
        }
    }

    func testFailedTranscriptionMarksJobFailedWithoutDBWrite() async throws {
        let recordingsDirectory = try makeTemporaryDirectory(
            prefix: "OfflineTranscriptionCoordinatorTests-Failure"
        )
        defer { cleanup(recordingsDirectory) }

        let fileURL = try makeExistingFile(named: "broken.wav", in: recordingsDirectory)
        let transcriber = ScriptedTranscriber(
            steps: [.immediate(.failure(PersonalScribeError.transcriptionFailure))]
        )
        let runtime = OfflineRuntimeSpy(transcribers: ["batch": transcriber])
        let repository = TranscriptRepositorySpy()
        let coordinator = makeCoordinator(
            runtime: runtime,
            repository: repository,
            sessionGate: SessionGateSpy(initialState: .idle),
            defaultBatchDescriptorID: { "batch" },
            fileSource: TestFileSource(buffersByURL: [fileURL.standardizedFileURL: [makeBuffer()]])
        )

        let jobID = await coordinator.enqueueFile(url: fileURL, descriptorID: "batch", diarize: false)
        let failedJob = try await waitForJob(id: jobID, in: coordinator) { job in
            job.status == OfflineTranscriptionCoordinator.JobStatus.failed(
                reason: .transcriptionFailed
            )
        }
        let appendedEntries = await repository.appendedEntries()

        XCTAssertEqual(
            failedJob.status,
            OfflineTranscriptionCoordinator.JobStatus.failed(reason: .transcriptionFailed)
        )
        XCTAssertTrue(appendedEntries.isEmpty)
    }
}

private extension OfflineTranscriptionCoordinatorTests {
    func makeCoordinator(
        runtime: OfflineRuntimeSpy,
        repository: TranscriptRepositorySpy,
        sessionGate: SessionGateSpy,
        defaultBatchDescriptorID: @escaping @Sendable () -> String?,
        recordingsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.recordingsDirectory() },
        now: @escaping @Sendable () -> Date = Date.init,
        fileSource: any FileSourceAudioStreaming = TestFileSource()
    ) -> OfflineTranscriptionCoordinator {
        OfflineTranscriptionCoordinator(
            runtime: runtime,
            defaultBatchDescriptorID: defaultBatchDescriptorID,
            fileSource: fileSource,
            repository: repository,
            sessionGate: sessionGate,
            recordingsDirectory: recordingsDirectory,
            now: now,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.transcription)
        )
    }

    func waitForJob(
        id: UUID,
        in coordinator: OfflineTranscriptionCoordinator,
        timeout: Duration = .seconds(2),
        predicate: @escaping @Sendable (OfflineTranscriptionCoordinator.Job) -> Bool
    ) async throws -> OfflineTranscriptionCoordinator.Job {
        try await waitForValue(timeout: timeout) {
            let snapshot = await coordinator.snapshot()
            return snapshot.first(where: { $0.id == id && predicate($0) })
        }
    }

    func waitForValue<T: Sendable>(
        timeout: Duration,
        pollInterval: Duration = .milliseconds(10),
        operation: @escaping @Sendable () async -> T?
    ) async throws -> T {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clock.now < deadline {
            if let value = await operation() {
                return value
            }
            try await Task.sleep(for: pollInterval)
        }

        throw WaitTimeoutError()
    }

    func observeSnapshots(
        from coordinator: OfflineTranscriptionCoordinator,
        until predicate: @escaping @Sendable ([OfflineTranscriptionCoordinator.Job]) -> Bool
    ) async throws -> SnapshotObservation {
        let stream = await coordinator.snapshotStream()
        var maxInFlightCount = 0

        for await snapshot in stream {
            maxInFlightCount = max(
                maxInFlightCount,
                snapshot.filter { $0.status.isInFlight }.count
            )
            if predicate(snapshot) {
                return SnapshotObservation(maxInFlightCount: maxInFlightCount)
            }
        }

        throw WaitTimeoutError()
    }

    func makeResult(text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(250)
        )
    }

    func makeBuffer(sampleCount: Int = 1_600) -> PCMBuffer {
        try! PCMBuffer( // swiftlint:disable:this force_try
            samples: Array(repeating: 0.25, count: sampleCount),
            timestamp: ContinuousClock().now
        )
    }

    func makeExistingFile(named name: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name, isDirectory: false).standardizedFileURL
        try Data("audio".utf8).write(to: url)
        return url
    }

    func makeTemporaryDirectory(prefix: String) throws -> URL {
        let url = fileManager.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    func cleanup(_ directory: URL) {
        try? fileManager.removeItem(at: directory)
    }
}

private struct SnapshotObservation {
    let maxInFlightCount: Int
}

private struct WaitTimeoutError: Error {}

private extension OfflineTranscriptionCoordinator.JobStatus {
    var isInFlight: Bool {
        if case .inFlight = self {
            return true
        }
        return false
    }

    var isTerminal: Bool {
        switch self {
        case .completed, .failed, .cancelled:
            true
        case .queued, .inFlight:
            false
        }
    }
}

private struct TestFileSource: FileSourceAudioStreaming, Sendable {
    let buffersByURL: [URL: [PCMBuffer]]
    let errorsByURL: [URL: any Error & Sendable]

    init(
        buffersByURL: [URL: [PCMBuffer]] = [:],
        errorsByURL: [URL: any Error & Sendable] = [:]
    ) {
        self.buffersByURL = buffersByURL
        self.errorsByURL = errorsByURL
    }

    func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error> {
        let standardizedURL = url.standardizedFileURL

        return AsyncThrowingStream { continuation in
            if let error = errorsByURL[standardizedURL] {
                continuation.finish(throwing: error)
                return
            }

            for buffer in buffersByURL[standardizedURL] ?? [try! PCMBuffer( // swiftlint:disable:this force_try
                samples: Array(repeating: 0.5, count: 1_600),
                timestamp: ContinuousClock().now
            )] {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }
}

private actor OfflineRuntimeSpy: OfflineTranscriptionRuntimeProviding {
    private let transcribersByID: [String: any Transcriber]
    private let diarizerInstance: any SpeakerDiarizer
    private var requestedDescriptorIDsStorage: [String] = []

    init(
        transcribers: [String: any Transcriber],
        diarizer: any SpeakerDiarizer = ScriptedDiarizer()
    ) {
        self.transcribersByID = transcribers
        self.diarizerInstance = diarizer
    }

    func transcriber(for descriptorID: String) async throws -> any Transcriber {
        requestedDescriptorIDsStorage.append(descriptorID)
        guard let transcriber = transcribersByID[descriptorID] else {
            throw PersonalScribeError.modelLoadFailure
        }
        return transcriber
    }

    func diarizer() async throws -> any SpeakerDiarizer {
        diarizerInstance
    }

    func requestedDescriptorIDs() -> [String] {
        requestedDescriptorIDsStorage
    }
}

private actor SessionGateSpy: SessionGateProviding {
    private var state: SessionState
    private var continuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]

    init(initialState: SessionState) {
        state = initialState
    }

    func isLiveSessionActive() async -> Bool {
        switch state {
        case .capturing, .holdRecording, .transcribing:
            true
        case .idle, .completed, .shortExit, .error:
            false
        }
    }

    func stateStream() async -> AsyncStream<SessionState> {
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(state)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
                }
            }
        }
    }

    func setState(_ newState: SessionState) {
        state = newState
        for continuation in continuations.values {
            continuation.yield(newState)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}

private actor TranscriptRepositorySpy: TranscriptAppending, TranscriptAudioFilenameNullifying {
    private var appendedEntriesStorage: [TranscriptEntry] = []
    private var nullifiedFilenamesStorage: [[String]] = []

    func append(_ entry: TranscriptEntry) async throws {
        appendedEntriesStorage.append(entry)
    }

    func nullifyAudioFilenames(_ filenames: [String]) async throws {
        nullifiedFilenamesStorage.append(filenames)
    }

    func appendedEntries() -> [TranscriptEntry] {
        appendedEntriesStorage
    }

    func nullifiedFilenames() -> [[String]] {
        nullifiedFilenamesStorage
    }
}

private actor ScriptedTranscriber: Transcriber {
    enum Step {
        case immediate(Result<TranscriptionResult, any Error & Sendable>)
        case delayed(Duration, Result<TranscriptionResult, any Error & Sendable>)
    }

    nonisolated let capabilities = TranscriberCapabilities()
    private let steps: [Step]
    private var callCount = 0

    init(steps: [Step] = []) {
        self.steps = steps
    }

    func downloadIfNeeded() async throws {}

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cleanup() async {}

    func releaseIdleResources() async {}

    func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        let defaultStep: Step = .immediate(.success(TranscriptionResult(
            text: "default",
            audioDuration: audio.duration,
            processingDuration: .milliseconds(10)
        )))
        let step = if callCount < steps.count {
            steps[callCount]
        } else {
            defaultStep
        }
        callCount += 1

        switch step {
        case .immediate(let result):
            return try result.get()
        case .delayed(let duration, let result):
            try await Task.sleep(for: duration)
            return try result.get()
        }
    }
}

private actor ScriptedDiarizer: SpeakerDiarizer {
    func downloadIfNeeded() async throws {}

    func prepare() async throws {}

    nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            continuation.finish()
        }
    }

    func cleanup() async {}

    func releaseIdleResources() async {}

    nonisolated func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { continuation in
            continuation.yield(.terminal([]))
            continuation.finish()
        }
    }
}
