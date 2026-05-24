import Foundation
import PersonalScribeCore
import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class OfflineTranscriptionTabViewModelTests: XCTestCase {
    func testHandleFileDropEnqueuesEachURL() async {
        let harness = makeHarness()
        let urls = [
            URL(fileURLWithPath: "/tmp/alpha.wav"),
            URL(fileURLWithPath: "/tmp/bravo.m4a"),
        ]

        await harness.viewModel.handleFileDrop(urls)

        let enqueued = await harness.coordinator.enqueuedURLs()
        XCTAssertEqual(enqueued, urls)
    }

    func testHandleFileDropFiltersUnsupportedExtensions() async {
        let harness = makeHarness()
        let supported = URL(fileURLWithPath: "/tmp/alpha.wav")
        let ignored = URL(fileURLWithPath: "/tmp/notes.txt")

        await harness.viewModel.handleFileDrop([supported, ignored])

        let enqueued = await harness.coordinator.enqueuedURLs()
        XCTAssertEqual(enqueued, [supported])
    }

    func testSelectingCompletedJobLoadsTranscriptText() async throws {
        let transcriptID = UUID()
        let jobID = UUID()
        let entry = makeEntry(id: transcriptID, text: "Loaded transcript")
        let harness = makeHarness(entries: [entry])
        await harness.coordinator.emitSnapshot([
            makeCompletedJob(id: jobID, transcriptID: transcriptID, enqueuedAt: Date())
        ])

        try await waitUntil(description: "jobs published") {
            harness.viewModel.jobs.count == 1
        }

        await harness.viewModel.selectCompletedJob(id: jobID)

        XCTAssertEqual(harness.viewModel.selectedCompletedJobID, jobID)
        XCTAssertEqual(harness.viewModel.selectedTranscriptText, "Loaded transcript")
        XCTAssertNil(harness.viewModel.selectedTranscriptErrorMessage)
    }

    func testSelectingNonexistentTranscriptShowsLoadFailure() async throws {
        let harness = makeHarness(entries: [])
        let jobID = UUID()
        await harness.coordinator.emitSnapshot([
            makeCompletedJob(id: jobID, transcriptID: UUID(), enqueuedAt: Date())
        ])

        try await waitUntil(description: "jobs published") {
            harness.viewModel.jobs.count == 1
        }

        await harness.viewModel.selectCompletedJob(id: jobID)

        XCTAssertEqual(harness.viewModel.selectedCompletedJobID, jobID)
        XCTAssertNil(harness.viewModel.selectedTranscriptText)
        XCTAssertEqual(harness.viewModel.selectedTranscriptErrorMessage, "Couldn't load transcript.")
    }

    func testModelPickerChangePersistsToPreference() {
        let defaults = ephemeralDefaults()
        let modelService = makeModelService(defaults: defaults)
        let viewModel = OfflineTranscriptionTabViewModel(
            transcriptReader: FakeTranscriptReader(entries: []),
            coordinator: FakeOfflineTranscriptionCoordinator(),
            modelService: modelService,
            defaults: defaults
        )
        let alternative = viewModel.availableDescriptors.first {
            $0.id != viewModel.selectedDescriptorID
        }
        guard let descriptor = alternative else {
            return XCTFail("Expected at least two ASR descriptors in the model catalog")
        }

        viewModel.setSelectedDescriptorID(descriptor.id)

        XCTAssertEqual(
            defaults.string(forKey: OfflineTranscriptionBatchModelPreference.key),
            descriptor.id
        )
    }

    func testDiarizationToggleChangePersistsToPreference() {
        let defaults = ephemeralDefaults()
        let viewModel = makeHarness(defaults: defaults).viewModel

        viewModel.setDiarizationEnabled(true)

        XCTAssertTrue(defaults.bool(forKey: OfflineTranscriptionDiarizationPreference.key))
    }

    func testJobsPublishedNewestFirst() async throws {
        let harness = makeHarness()
        let older = makeQueuedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            url: URL(fileURLWithPath: "/tmp/older.wav"),
            enqueuedAt: Date(timeIntervalSince1970: 10)
        )
        let newest = makeQueuedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
            url: URL(fileURLWithPath: "/tmp/newest.wav"),
            enqueuedAt: Date(timeIntervalSince1970: 30)
        )
        let middle = makeQueuedJob(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
            url: URL(fileURLWithPath: "/tmp/middle.wav"),
            enqueuedAt: Date(timeIntervalSince1970: 20)
        )

        await harness.coordinator.emitSnapshot([older, newest, middle])

        try await waitUntil(description: "jobs sorted newest first") {
            harness.viewModel.jobs.map(\.id) == [newest.id, middle.id, older.id]
        }

        XCTAssertEqual(harness.viewModel.jobs.map(\.id), [newest.id, middle.id, older.id])
    }
}

@MainActor
private extension OfflineTranscriptionTabViewModelTests {
    func makeHarness(
        entries: [TranscriptEntry] = [],
        defaults: UserDefaults? = nil
    ) -> (
        viewModel: OfflineTranscriptionTabViewModel,
        coordinator: FakeOfflineTranscriptionCoordinator,
        reader: FakeTranscriptReader,
        defaults: UserDefaults
    ) {
        let resolvedDefaults = defaults ?? ephemeralDefaults()
        let coordinator = FakeOfflineTranscriptionCoordinator()
        let reader = FakeTranscriptReader(entries: entries)
        let viewModel = OfflineTranscriptionTabViewModel(
            transcriptReader: reader,
            coordinator: coordinator,
            modelService: makeModelService(defaults: resolvedDefaults),
            defaults: resolvedDefaults
        )
        return (viewModel, coordinator, reader, resolvedDefaults)
    }

    func makeModelService(defaults: UserDefaults) -> ActiveModelService {
        ActiveModelService(
            defaults: defaults,
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.session)
        )
    }

    func makeEntry(
        id: UUID = UUID(),
        text: String,
        timestamp: Date = Date(timeIntervalSince1970: 100)
    ) -> TranscriptEntry {
        TranscriptEntry(
            id: id,
            timestamp: timestamp,
            text: text,
            audioDuration: 1.0,
            processingDuration: 0.2
        )
    }

    func makeQueuedJob(
        id: UUID,
        url: URL,
        enqueuedAt: Date
    ) -> OfflineTranscriptionCoordinator.Job {
        OfflineTranscriptionCoordinator.Job(
            id: id,
            url: url,
            sourceFilename: url.lastPathComponent,
            descriptorID: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            diarize: false,
            recipeOverride: nil,
            enqueuedAt: enqueuedAt,
            status: .queued
        )
    }

    func makeCompletedJob(
        id: UUID,
        transcriptID: UUID,
        enqueuedAt: Date
    ) -> OfflineTranscriptionCoordinator.Job {
        OfflineTranscriptionCoordinator.Job(
            id: id,
            url: URL(fileURLWithPath: "/tmp/completed.wav"),
            sourceFilename: "completed.wav",
            descriptorID: BuiltInModelCatalog.parakeetTDT06Bv2.id,
            diarize: false,
            recipeOverride: nil,
            enqueuedAt: enqueuedAt,
            status: .completed(transcriptID: transcriptID)
        )
    }

    func ephemeralDefaults() -> UserDefaults {
        let suiteName = "OfflineTranscriptionTabViewModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func waitUntil(
        description: String,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for \(description)")
    }
}

private actor FakeTranscriptReader: TranscriptReading {
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
}

private actor FakeOfflineTranscriptionCoordinator: OfflineTranscriptionJobManaging {
    private var jobs: [OfflineTranscriptionCoordinator.Job] = []
    private var continuations: [UUID: AsyncStream<[OfflineTranscriptionCoordinator.Job]>.Continuation] = [:]
    private var enqueuedURLStorage: [URL] = []

    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        enqueuedURLStorage.append(url)
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
        let id = UUID()
        let snapshot = jobs
        return AsyncStream { continuation in
            self.continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeContinuation(id: id)
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

    func enqueuedURLs() -> [URL] {
        enqueuedURLStorage
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
