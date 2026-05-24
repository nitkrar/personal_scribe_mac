import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class OfflineRetranscriptionActionTests: XCTestCase {
    func testRetranscribeMenuItemClickInvokesCoordinatorWithSourceFilename() async {
        let entry = makeEntry(text: "latest", audioFilename: "latest.wav")
        let transcriptReader = FakeTranscriptReader(entries: [entry])
        let coordinator = FakeOfflineTranscriptionCoordinator()
        let clipboardWriter = ClipboardWriterSpy()
        let action = OfflineRetranscriptionAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            toastBroadcaster: ToastBroadcaster(),
            clipboardWriter: clipboardWriter.write(_:)
        )

        await action.performLatestRecordingRetranscription()

        let calls = await coordinator.retranscribeCalls()
        XCTAssertEqual(calls, ["latest.wav"])
        XCTAssertTrue(clipboardWriter.writes.isEmpty)
    }

    func testRetranscribeSuccessCopiesTextToClipboardAndPostsToast() async throws {
        let transcriptID = UUID()
        let entry = makeEntry(id: transcriptID, text: "fresh transcript", audioFilename: "latest.wav")
        let transcriptReader = FakeTranscriptReader(entries: [entry])
        let coordinator = FakeOfflineTranscriptionCoordinator()
        let broadcaster = ToastBroadcaster()
        let clipboardWriter = ClipboardWriterSpy()
        let action = OfflineRetranscriptionAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            toastBroadcaster: broadcaster,
            clipboardWriter: clipboardWriter.write(_:)
        )
        var messages: [ResponseCardMessage] = []
        let expectation = expectation(description: "success toast posted")
        let cancellable = broadcaster.publisher.sink { message in
            messages.append(message)
            expectation.fulfill()
        }
        defer { _ = cancellable }

        await action.performRetranscription(sourceFilename: "latest.wav")
        try await waitUntil(description: "retranscription observer subscribes") {
            await coordinator.continuationCount() >= 1
        }

        let completedJob = OfflineTranscriptionCoordinator.Job(
            id: await coordinator.nextJobID(),
            url: URL(fileURLWithPath: "/tmp/latest.wav"),
            sourceFilename: "latest.wav",
            descriptorID: "asr-test",
            diarize: false,
            recipeOverride: .fixedDictation,
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .completed(transcriptID: transcriptID)
        )
        await coordinator.emitSnapshot([completedJob])

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertEqual(clipboardWriter.writes, ["fresh transcript"])
        XCTAssertEqual(messages, [.success("Re-transcribed → clipboard")])
    }

    func testRetranscribeAudioMissingPostsLinkRemovedToast() async throws {
        let transcriptReader = FakeTranscriptReader(entries: [])
        let coordinator = FakeOfflineTranscriptionCoordinator()
        let broadcaster = ToastBroadcaster()
        let clipboardWriter = ClipboardWriterSpy()
        let action = OfflineRetranscriptionAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            toastBroadcaster: broadcaster,
            clipboardWriter: clipboardWriter.write(_:)
        )
        var messages: [ResponseCardMessage] = []
        let expectation = expectation(description: "missing-audio toast posted")
        let cancellable = broadcaster.publisher.sink { message in
            messages.append(message)
            expectation.fulfill()
        }
        defer { _ = cancellable }

        await action.performRetranscription(sourceFilename: "missing.wav")
        try await waitUntil(description: "retranscription observer subscribes") {
            await coordinator.continuationCount() >= 1
        }

        let failedJob = OfflineTranscriptionCoordinator.Job(
            id: await coordinator.nextJobID(),
            url: URL(fileURLWithPath: "/tmp/missing.wav"),
            sourceFilename: "missing.wav",
            descriptorID: "asr-test",
            diarize: false,
            recipeOverride: .fixedDictation,
            enqueuedAt: Date(timeIntervalSince1970: 1_700_000_000),
            status: .failed(reason: .audioMissing)
        )
        await coordinator.emitSnapshot([failedJob])

        await fulfillment(of: [expectation], timeout: 1.0)
        XCTAssertTrue(clipboardWriter.writes.isEmpty)
        XCTAssertEqual(messages, [.error("Audio file no longer available — link removed")])
    }

    private func makeEntry(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000),
        audioFilename: String? = nil
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: 3.0,
            processingDuration: 0.5,
            audioFilename: audioFilename
        )
    }
}

private actor FakeTranscriptReader: TranscriptReading {
    private var entries: [TranscriptEntry]

    init(entries: [TranscriptEntry]) {
        self.entries = entries
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(entries.prefix(limit))
    }

    func search(query: String) async -> [TranscriptEntry] {
        entries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func all() async -> [TranscriptEntry] {
        entries
    }
}

private actor FakeOfflineTranscriptionCoordinator: OfflineTranscriptionJobManaging {
    private let fixedJobID = UUID()
    private var jobs: [OfflineTranscriptionCoordinator.Job] = []
    private var continuations: [UUID: AsyncStream<[OfflineTranscriptionCoordinator.Job]>.Continuation] = [:]
    private var retranscribeCallsStorage: [String] = []

    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        UUID()
    }

    func reTranscribe(sourceFilename: String) async -> UUID {
        retranscribeCallsStorage.append(sourceFilename)
        return fixedJobID
    }

    func cancelJob(id: UUID) async {}

    func dequeueJob(id: UUID) async {}

    func snapshot() async -> [OfflineTranscriptionCoordinator.Job] {
        jobs
    }

    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]> {
        let continuationID = UUID()
        let snapshot = jobs
        return AsyncStream { continuation in
            self.continuations[continuationID] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: continuationID)
                }
            }
            continuation.yield(snapshot)
        }
    }

    func emitSnapshot(_ snapshot: [OfflineTranscriptionCoordinator.Job]) {
        jobs = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    func retranscribeCalls() -> [String] {
        retranscribeCallsStorage
    }

    func continuationCount() -> Int {
        continuations.count
    }

    func nextJobID() -> UUID {
        fixedJobID
    }

    deinit {
        for continuation in continuations.values {
            continuation.finish()
        }
    }

    private func removeContinuation(id: UUID) {
        continuations[id] = nil
    }
}

@MainActor
private final class ClipboardWriterSpy: @unchecked Sendable {
    private(set) var writes: [String] = []

    func write(_ text: String) {
        writes.append(text)
    }
}

private func waitUntil(
    description: String,
    timeout: Duration = .seconds(1),
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
}
