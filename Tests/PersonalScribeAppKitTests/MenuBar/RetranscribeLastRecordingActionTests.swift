import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class RetranscribeLastRecordingActionTests: XCTestCase {
    func testRetranscribeMenuItemDisabledWhenNoAudioRows() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            canRetranscribeLastRecording: false
        )

        guard let action = retractranscribeMenuItem(in: model) else {
            return XCTFail("Expected Retranscribe Last Recording action in menu")
        }
        XCTAssertFalse(action.isEnabled)
    }

    func testRetranscribeMenuItemEnabledWhenAudioRowExists() {
        let model = StatusItemMenuModel.makeUnified(
            sessionState: .idle,
            micPermission: .granted,
            inputMonitoringPermission: .granted,
            activeModeName: WorkflowMode.dictation.name,
            canRetranscribeLastRecording: true
        )

        guard let action = retractranscribeMenuItem(in: model) else {
            return XCTFail("Expected Retranscribe Last Recording action in menu")
        }
        XCTAssertTrue(action.isEnabled)
    }

    func testRetranscribeMenuItemClickInvokesCoordinatorWithSourceFilename() async {
        let sourceFilename = "recording.wav"
        let transcriptReader = RetranscribeTranscriptReaderFake()
        await transcriptReader.seed(
            all: [],
            mostRecentAudio: makeEntry(text: "previous", audioFilename: sourceFilename)
        )
        let coordinator = RetranscribeCoordinatorSpy(terminalStatus: .cancelled)
        let clipboardWriter = RetranscribeClipboardWriterSpy()
        let toastBroadcaster = ToastPostingSpy()
        let action = RetranscribeLastRecordingAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter.write(_:),
            toastBroadcaster: toastBroadcaster,
            notificationCenter: NotificationCenter()
        )

        await action.perform()

        let calls = await coordinator.reTranscribeCalls()
        XCTAssertEqual(calls, [sourceFilename])
        XCTAssertTrue(clipboardWriter.writes.isEmpty)
    }

    func testRetranscribeSuccessCopiesTextToClipboardAndPostsToast() async {
        let sourceFilename = "recording.wav"
        let transcriptID = UUID()
        let transcriptReader = RetranscribeTranscriptReaderFake()
        await transcriptReader.seed(
            all: [makeEntry(id: transcriptID, text: "retranscribed text", audioFilename: sourceFilename)],
            mostRecentAudio: makeEntry(text: "previous", audioFilename: sourceFilename)
        )
        let coordinator = RetranscribeCoordinatorSpy(
            terminalStatus: .completed(transcriptID: transcriptID)
        )
        let clipboardWriter = RetranscribeClipboardWriterSpy()
        let toastBroadcaster = ToastPostingSpy()
        let action = RetranscribeLastRecordingAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter.write(_:),
            toastBroadcaster: toastBroadcaster,
            notificationCenter: NotificationCenter()
        )

        await action.perform()

        let calls = await coordinator.reTranscribeCalls()
        XCTAssertEqual(calls, [sourceFilename])
        XCTAssertEqual(clipboardWriter.writes, ["retranscribed text"])
        XCTAssertEqual(
            toastBroadcaster.messages,
            [.init(text: "Re-transcribed → clipboard", autoDismissAfter: 3.0)]
        )
    }

    func testRetranscribeAudioMissingPostsLinkRemovedToast() async {
        let sourceFilename = "recording.wav"
        let transcriptReader = RetranscribeTranscriptReaderFake()
        await transcriptReader.seed(
            all: [],
            mostRecentAudio: makeEntry(text: "previous", audioFilename: sourceFilename)
        )
        let coordinator = RetranscribeCoordinatorSpy(
            terminalStatus: .failed(reason: .audioMissing)
        )
        let clipboardWriter = RetranscribeClipboardWriterSpy()
        let toastBroadcaster = ToastPostingSpy()
        let action = RetranscribeLastRecordingAction(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter.write(_:),
            toastBroadcaster: toastBroadcaster,
            notificationCenter: NotificationCenter()
        )

        await action.perform()

        XCTAssertTrue(clipboardWriter.writes.isEmpty)
        XCTAssertEqual(
            toastBroadcaster.messages,
            [.init(text: "Audio file no longer available — link removed", autoDismissAfter: 3.0)]
        )
    }
}

// MARK: - Helpers

@MainActor
private extension RetranscribeLastRecordingActionTests {
    func makeEntry(
        id: UUID = UUID(),
        text: String,
        audioFilename: String? = nil,
        timestamp: Date = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: 3,
            processingDuration: 0.5,
            audioFilename: audioFilename
        )
    }

    func retractranscribeMenuItem(
        in model: StatusItemMenuModel
    ) -> StatusItemMenuModel.ActionItem? {
        model.items.compactMap { item in
            if case let .action(action) = item,
               action.id == .reTranscribeLastRecording {
                return action
            }
            return nil
        }.first
    }
}

private actor RetranscribeTranscriptReaderFake: TranscriptReading {
    private var recentEntries: [TranscriptEntry] = []
    private var allEntries: [TranscriptEntry] = []
    private var mostRecentAudioEntry: TranscriptEntry?

    func seed(
        recent: [TranscriptEntry] = [],
        all: [TranscriptEntry] = [],
        mostRecentAudio: TranscriptEntry? = nil
    ) {
        recentEntries = recent
        allEntries = all
        mostRecentAudioEntry = mostRecentAudio
    }

    func recent(limit: Int) async -> [TranscriptEntry] {
        Array(recentEntries.prefix(limit))
    }

    func search(query: String) async -> [TranscriptEntry] {
        allEntries.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    func all() async -> [TranscriptEntry] {
        allEntries
    }

    func mostRecentEntryWithAudio() async -> TranscriptEntry? {
        mostRecentAudioEntry
    }
}

private actor RetranscribeCoordinatorSpy: OfflineTranscriptionCoordinating {
    private let terminalStatus: OfflineTranscriptionCoordinator.JobStatus
    private var jobs: [OfflineTranscriptionCoordinator.Job] = []
    private var reTranscribeCallsStorage: [String] = []

    init(terminalStatus: OfflineTranscriptionCoordinator.JobStatus) {
        self.terminalStatus = terminalStatus
    }

    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        UUID()
    }

    func reTranscribe(sourceFilename: String) async -> UUID {
        reTranscribeCallsStorage.append(sourceFilename)
        let jobID = UUID()
        jobs = [
            OfflineTranscriptionCoordinator.Job(
                id: jobID,
                url: URL(fileURLWithPath: sourceFilename).standardizedFileURL,
                descriptorID: "batch",
                diarize: false,
                recipeOverride: .fixedDictation,
                status: terminalStatus
            )
        ]
        return jobID
    }

    func cancelJob(id: UUID) async {}

    func dequeueJob(id: UUID) async {}

    func snapshot() async -> [OfflineTranscriptionCoordinator.Job] {
        jobs
    }

    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]> {
        let jobs = self.jobs
        return AsyncStream { continuation in
            continuation.yield(jobs)
        }
    }

    func reTranscribeCalls() -> [String] {
        reTranscribeCallsStorage
    }
}

@MainActor
private final class RetranscribeClipboardWriterSpy: @unchecked Sendable {
    private(set) var writes: [String] = []

    func write(_ text: String) {
        writes.append(text)
    }
}

@MainActor
private final class ToastPostingSpy: ToastPosting, @unchecked Sendable {
    private(set) var messages: [ToastBroadcaster.Message] = []

    func post(_ message: ToastBroadcaster.Message) {
        messages.append(message)
    }
}
