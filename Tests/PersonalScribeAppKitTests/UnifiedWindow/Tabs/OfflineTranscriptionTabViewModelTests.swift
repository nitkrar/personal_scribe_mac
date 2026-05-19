import Foundation
import PersonalScribeCore
import XCTest
@testable import PersonalScribeAppKit
@testable import PersonalScribeSession

@MainActor
final class OfflineTranscriptionTabViewModelTests: XCTestCase {
    func testHandleFileDropEnqueuesEachURL() async {
        let harness = makeHarness()
        let firstURL = URL(fileURLWithPath: "/tmp/first.wav")
        let secondURL = URL(fileURLWithPath: "/tmp/second.mp3")

        await harness.viewModel.handleFileDrop([firstURL, secondURL])

        let calls = await harness.coordinator.enqueueCalls()
        XCTAssertEqual(calls.map(\.url), [firstURL.standardizedFileURL, secondURL.standardizedFileURL])
        XCTAssertEqual(calls.map(\.descriptorID), [harness.viewModel.selectedModelID, harness.viewModel.selectedModelID])
        XCTAssertEqual(calls.map(\.diarize), [false, false])
    }

    func testHandleFileDropFiltersUnsupportedExtensions() async {
        let harness = makeHarness()
        let ignoredURL = URL(fileURLWithPath: "/tmp/notes.txt")
        let acceptedURL = URL(fileURLWithPath: "/tmp/audio.wav")

        await harness.viewModel.handleFileDrop([ignoredURL, acceptedURL])

        let calls = await harness.coordinator.enqueueCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.url, acceptedURL.standardizedFileURL)
    }

    func testSelectingCompletedJobLoadsTranscriptText() async {
        let transcriptID = UUID()
        let jobID = UUID()
        let harness = makeHarness(
            entries: [
                TranscriptEntry(
                    id: transcriptID,
                    timestamp: Date(),
                    text: "Loaded transcript body",
                    audioDuration: 4,
                    processingDuration: 1
                )
            ]
        )
        await harness.coordinator.publish([
            makeCompletedJob(
                id: jobID,
                transcriptID: transcriptID,
                filename: "meeting.wav"
            )
        ])

        await waitUntil {
            harness.viewModel.jobs.count == 1
        }

        harness.viewModel.selectedCompletedJobID = jobID

        await waitUntil {
            harness.viewModel.sidePaneText == "Loaded transcript body"
        }

        XCTAssertNil(harness.viewModel.sidePaneErrorMessage)
    }

    func testSelectingNonexistentTranscriptShowsLoadFailure() async {
        let missingTranscriptID = UUID()
        let jobID = UUID()
        let harness = makeHarness()
        await harness.coordinator.publish([
            makeCompletedJob(
                id: jobID,
                transcriptID: missingTranscriptID,
                filename: "missing.wav"
            )
        ])

        await waitUntil {
            harness.viewModel.jobs.count == 1
        }

        harness.viewModel.selectedCompletedJobID = jobID

        await waitUntil {
            harness.viewModel.sidePaneErrorMessage != nil
        }

        XCTAssertNil(harness.viewModel.sidePaneText)
        XCTAssertEqual(
            harness.viewModel.sidePaneErrorMessage,
            "Couldn’t load the selected transcript."
        )
    }

    func testModelPickerChangePersistsToPreference() {
        let defaults = isolatedDefaults()
        let first = BuiltInModelCatalog.parakeetTDTCTC110M
        let second = BuiltInModelCatalog.parakeetTDT06Bv2
        let harness = makeHarness(
            defaults: defaults,
            registeredModels: [first, second]
        )

        harness.viewModel.selectedModelID = second.id

        XCTAssertEqual(
            defaults.string(forKey: OfflineTranscriptionBatchModelPreference.key),
            second.id
        )
    }

    func testDiarizationToggleChangePersistsToPreference() {
        let defaults = isolatedDefaults()
        let harness = makeHarness(defaults: defaults)

        harness.viewModel.diarizationEnabled = true

        XCTAssertEqual(
            defaults.object(forKey: OfflineTranscriptionDiarizationPreference.key) as? Bool,
            true
        )
    }
}

// MARK: - Helpers

@MainActor
private extension OfflineTranscriptionTabViewModelTests {
    func makeHarness(
        defaults: UserDefaults? = nil,
        registeredModels: [ModelDescriptor] = [BuiltInModelCatalog.parakeetTDTCTC110M],
        entries: [TranscriptEntry] = []
    ) -> (
        viewModel: OfflineTranscriptionTabViewModel,
        coordinator: OfflineTranscriptionCoordinatorSpy,
        reader: OfflineTranscriptionReaderSpy,
        defaults: UserDefaults
    ) {
        let resolvedDefaults = defaults ?? isolatedDefaults()
        let coordinator = OfflineTranscriptionCoordinatorSpy()
        let reader = OfflineTranscriptionReaderSpy(entries: entries)
        let modelService = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [.asr: registeredModels[0].id],
                defaults: resolvedDefaults
            ),
            registeredModels: registeredModels,
            isDownloaded: { _ in true },
            download: { _, _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
        let viewModel = OfflineTranscriptionTabViewModel(
            coordinator: coordinator,
            transcriptReader: reader,
            modelService: modelService,
            defaults: resolvedDefaults
        )
        return (viewModel, coordinator, reader, resolvedDefaults)
    }

    func makeCompletedJob(
        id: UUID = UUID(),
        transcriptID: UUID,
        filename: String
    ) -> OfflineTranscriptionCoordinator.Job {
        OfflineTranscriptionCoordinator.Job(
            id: id,
            url: URL(fileURLWithPath: "/tmp/\(filename)").standardizedFileURL,
            descriptorID: "batch-model",
            diarize: false,
            recipeOverride: nil,
            status: .completed(transcriptID: transcriptID)
        )
    }

    func isolatedDefaults() -> UserDefaults {
        let suiteName = "OfflineTranscriptionTabViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    func waitUntil(
        timeout: Duration = .seconds(1),
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: @escaping @MainActor () -> Bool
    ) async {
        let timeoutNanoseconds = UInt64(timeout.components.seconds) * 1_000_000_000
            + UInt64(timeout.components.attoseconds / 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds

        while DispatchTime.now().uptimeNanoseconds < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for condition", file: file, line: line)
    }
}

private actor OfflineTranscriptionCoordinatorSpy: OfflineTranscriptionCoordinating {
    struct EnqueueCall: Equatable {
        let url: URL
        let descriptorID: String
        let diarize: Bool
    }

    private var jobs: [OfflineTranscriptionCoordinator.Job] = []
    private var enqueueCallsStorage: [EnqueueCall] = []
    private var continuations: [UUID: AsyncStream<[OfflineTranscriptionCoordinator.Job]>.Continuation] = [:]

    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        enqueueCallsStorage.append(
            EnqueueCall(
                url: url.standardizedFileURL,
                descriptorID: descriptorID,
                diarize: diarize
            )
        )
        return UUID()
    }

    func reTranscribe(sourceFilename: String) async -> UUID {
        UUID()
    }

    func cancelJob(id: UUID) async {}

    func dequeueJob(id: UUID) async {}

    func snapshot() async -> [OfflineTranscriptionCoordinator.Job] {
        jobs
    }

    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]> {
        let continuationID = UUID()
        return AsyncStream { continuation in
            continuations[continuationID] = continuation
            continuation.yield(jobs)
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: continuationID)
                }
            }
        }
    }

    func publish(_ jobs: [OfflineTranscriptionCoordinator.Job]) {
        self.jobs = jobs
        for continuation in continuations.values {
            continuation.yield(jobs)
        }
    }

    func enqueueCalls() -> [EnqueueCall] {
        enqueueCallsStorage
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

private actor OfflineTranscriptionReaderSpy: TranscriptReading {
    private let entries: [TranscriptEntry]

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

    func mostRecentEntryWithAudio() async -> TranscriptEntry? {
        entries.first(where: { $0.audioFilename != nil })
    }
}
