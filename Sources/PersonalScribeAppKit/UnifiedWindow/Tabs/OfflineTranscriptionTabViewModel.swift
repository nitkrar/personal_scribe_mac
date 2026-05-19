import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

protocol OfflineTranscriptionCoordinating: Sendable {
    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID
    func reTranscribe(sourceFilename: String) async -> UUID
    func cancelJob(id: UUID) async
    func dequeueJob(id: UUID) async
    func snapshot() async -> [OfflineTranscriptionCoordinator.Job]
    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]>
}

extension OfflineTranscriptionCoordinator: OfflineTranscriptionCoordinating {}

actor DisabledOfflineTranscriptionCoordinator: OfflineTranscriptionCoordinating {
    func enqueueFile(url: URL, descriptorID: String, diarize: Bool) async -> UUID {
        UUID()
    }

    func reTranscribe(sourceFilename: String) async -> UUID {
        UUID()
    }

    func cancelJob(id: UUID) async {}

    func dequeueJob(id: UUID) async {}

    func snapshot() async -> [OfflineTranscriptionCoordinator.Job] {
        []
    }

    func snapshotStream() async -> AsyncStream<[OfflineTranscriptionCoordinator.Job]> {
        AsyncStream { continuation in
            continuation.yield([])
        }
    }
}

@MainActor
final class OfflineTranscriptionTabViewModel: ObservableObject {
    typealias Job = OfflineTranscriptionCoordinator.Job

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var availableModels: [ModelDescriptor]
    @Published var selectedModelID: String {
        didSet {
            OfflineTranscriptionBatchModelPreference.persist(selectedModelID, to: defaults)
        }
    }
    @Published var diarizationEnabled: Bool {
        didSet {
            OfflineTranscriptionDiarizationPreference.persist(diarizationEnabled, to: defaults)
        }
    }
    @Published var selectedCompletedJobID: UUID? {
        didSet {
            scheduleSelectedTranscriptLoad()
        }
    }
    @Published private(set) var sidePaneText: String?
    @Published private(set) var sidePaneErrorMessage: String?
    @Published private(set) var isLoadingSidePane = false

    var isSidePanePresented: Bool {
        selectedCompletedJobID != nil
    }

    private let coordinator: any OfflineTranscriptionCoordinating
    private let transcriptReader: any TranscriptReading
    private let defaults: UserDefaults
    private var snapshotObservationTask: Task<Void, Never>?
    private var transcriptLoadTask: Task<Void, Never>?

    init(
        coordinator: any OfflineTranscriptionCoordinating,
        transcriptReader: any TranscriptReading,
        modelService: ActiveModelService,
        defaults: UserDefaults = .standard
    ) {
        let availableModels = Self.resolveAvailableModels(from: modelService)
        let fallbackModelID = modelService.activeDescriptor(for: .asr)?.id
            ?? availableModels.first?.id
            ?? ""
        let resolvedModelID = OfflineTranscriptionBatchModelPreference.resolve(
            from: defaults
        ) {
            fallbackModelID
        }
        let normalizedModelID: String
        if availableModels.isEmpty || availableModels.contains(where: { $0.id == resolvedModelID }) {
            normalizedModelID = resolvedModelID
        } else {
            normalizedModelID = fallbackModelID
            OfflineTranscriptionBatchModelPreference.persist(normalizedModelID, to: defaults)
        }

        self.coordinator = coordinator
        self.transcriptReader = transcriptReader
        self.defaults = defaults
        self.availableModels = availableModels
        self.selectedModelID = normalizedModelID
        self.diarizationEnabled = OfflineTranscriptionDiarizationPreference.resolve(from: defaults)
        self.selectedCompletedJobID = nil
        self.sidePaneText = nil
        self.sidePaneErrorMessage = nil

        snapshotObservationTask = Task { [weak self] in
            guard let self else {
                return
            }
            let stream = await coordinator.snapshotStream()
            for await jobs in stream {
                await MainActor.run {
                    self.jobs = jobs
                    self.refreshSelectedTranscriptIfNeeded()
                }
            }
        }
    }

    deinit {
        snapshotObservationTask?.cancel()
        transcriptLoadTask?.cancel()
    }

    func handleFileDrop(_ urls: [URL]) async {
        await enqueueSupportedFiles(from: urls)
    }

    func handlePickedFiles(_ urls: [URL]) async {
        await enqueueSupportedFiles(from: urls)
    }

    func cancelJob(id: UUID) async {
        await coordinator.cancelJob(id: id)
    }

    func dequeueJob(id: UUID) async {
        await coordinator.dequeueJob(id: id)
    }

    func dismissSidePane() {
        selectedCompletedJobID = nil
    }
}

private extension OfflineTranscriptionTabViewModel {
    static let supportedExtensions: Set<String> = ["wav", "m4a", "mp3", "aac"]

    static func resolveAvailableModels(from modelService: ActiveModelService) -> [ModelDescriptor] {
        modelService.enabledModels(kind: .asr)
    }

    func enqueueSupportedFiles(from urls: [URL]) async {
        let supportedURLs = urls
            .map(\.standardizedFileURL)
            .filter { Self.supportedExtensions.contains($0.pathExtension.lowercased()) }

        for url in supportedURLs {
            _ = await coordinator.enqueueFile(
                url: url,
                descriptorID: selectedModelID,
                diarize: diarizationEnabled
            )
        }
    }

    func refreshSelectedTranscriptIfNeeded() {
        guard let selectedJobID = selectedCompletedJobID else {
            return
        }
        guard jobs.contains(where: { $0.id == selectedJobID }) else {
            selectedCompletedJobID = nil
            return
        }
        scheduleSelectedTranscriptLoad()
    }

    func scheduleSelectedTranscriptLoad() {
        transcriptLoadTask?.cancel()
        sidePaneText = nil
        sidePaneErrorMessage = nil

        guard let selectedCompletedJobID else {
            isLoadingSidePane = false
            return
        }
        guard let transcriptID = transcriptID(for: selectedCompletedJobID) else {
            isLoadingSidePane = false
            sidePaneErrorMessage = "Couldn’t load the selected transcript."
            return
        }

        isLoadingSidePane = true
        transcriptLoadTask = Task { [weak self] in
            guard let self else {
                return
            }
            let entries = await transcriptReader.all()
            guard Task.isCancelled == false else {
                return
            }
            let matchedEntry = entries.first(where: { $0.id == transcriptID })

            await MainActor.run {
                self.isLoadingSidePane = false
                if let matchedEntry {
                    self.sidePaneText = matchedEntry.text
                    self.sidePaneErrorMessage = nil
                } else {
                    self.sidePaneText = nil
                    self.sidePaneErrorMessage = "Couldn’t load the selected transcript."
                }
            }
        }
    }

    func transcriptID(for jobID: UUID) -> UUID? {
        guard let job = jobs.first(where: { $0.id == jobID }) else {
            return nil
        }
        guard case .completed(let transcriptID) = job.status else {
            return nil
        }
        return transcriptID
    }
}
