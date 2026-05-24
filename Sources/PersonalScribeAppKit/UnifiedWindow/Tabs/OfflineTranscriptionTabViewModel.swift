import Foundation
import PersonalScribeCore
import PersonalScribeSession

@MainActor
final class OfflineTranscriptionTabViewModel: ObservableObject {
    @Published private(set) var jobs: [OfflineTranscriptionCoordinator.Job] = []
    @Published private(set) var availableDescriptors: [ModelDescriptor]
    @Published private(set) var selectedDescriptorID: String
    @Published private(set) var diarizationEnabled: Bool
    @Published private(set) var selectedCompletedJobID: UUID?
    @Published private(set) var selectedTranscriptText: String?
    @Published private(set) var selectedTranscriptErrorMessage: String?

    private let transcriptReader: any TranscriptReading
    private let coordinator: (any OfflineTranscriptionJobManaging)?
    private let defaults: UserDefaults
    private var jobsObservationTask: Task<Void, Never>?

    init(
        transcriptReader: any TranscriptReading,
        coordinator: (any OfflineTranscriptionJobManaging)? = nil,
        modelService: ActiveModelService,
        defaults: UserDefaults = .standard
    ) {
        let persistedSelection = OfflineTranscriptionBatchModelPreference.resolve(
            from: defaults,
            modelService: modelService
        )
        let descriptors = Self.availableDescriptors(
            from: modelService,
            ensuringSelectionID: persistedSelection
        )
        let resolvedSelection = descriptors.first(where: { $0.id == persistedSelection })?.id
            ?? descriptors.first?.id
            ?? persistedSelection

        self.transcriptReader = transcriptReader
        self.coordinator = coordinator
        self.defaults = defaults
        self.availableDescriptors = descriptors
        self.selectedDescriptorID = resolvedSelection
        self.diarizationEnabled = OfflineTranscriptionDiarizationPreference.resolve(from: defaults)

        if resolvedSelection != persistedSelection {
            OfflineTranscriptionBatchModelPreference.persist(resolvedSelection, to: defaults)
        }

        jobsObservationTask = Task { [weak self] in
            await self?.observeJobs()
        }
    }

    var hasSelectedCompletedJob: Bool {
        selectedCompletedJobID != nil
    }

    var selectedCompletedJob: OfflineTranscriptionCoordinator.Job? {
        guard let selectedCompletedJobID else {
            return nil
        }
        return jobs.first { $0.id == selectedCompletedJobID }
    }

    func setSelectedDescriptorID(_ descriptorID: String) {
        guard selectedDescriptorID != descriptorID else {
            return
        }

        selectedDescriptorID = descriptorID
        OfflineTranscriptionBatchModelPreference.persist(descriptorID, to: defaults)
    }

    func setDiarizationEnabled(_ isEnabled: Bool) {
        guard diarizationEnabled != isEnabled else {
            return
        }

        diarizationEnabled = isEnabled
        OfflineTranscriptionDiarizationPreference.persist(isEnabled, to: defaults)
    }

    func handleFileDrop(_ urls: [URL]) async {
        await enqueueSupportedAudioURLs(urls)
    }

    func handlePickedFiles(_ urls: [URL]) async {
        await enqueueSupportedAudioURLs(urls)
    }

    func cancelJob(id: UUID) async {
        guard let coordinator else {
            return
        }

        await coordinator.cancelJob(id: id)
    }

    func dequeueJob(id: UUID) async {
        guard let coordinator else {
            return
        }

        await coordinator.dequeueJob(id: id)
    }

    func selectCompletedJob(id: UUID) async {
        guard let job = jobs.first(where: { $0.id == id }) else {
            return
        }
        guard case .completed(let transcriptID) = job.status else {
            return
        }

        selectedCompletedJobID = id
        selectedTranscriptText = nil
        selectedTranscriptErrorMessage = nil

        let entries = await transcriptReader.all()
        guard let entry = entries.first(where: { $0.id == transcriptID }) else {
            selectedTranscriptErrorMessage = "Couldn't load transcript."
            return
        }

        selectedTranscriptText = entry.text
    }

    func closeSelectedCompletedJob() {
        selectedCompletedJobID = nil
        selectedTranscriptText = nil
        selectedTranscriptErrorMessage = nil
    }

    isolated deinit {
        jobsObservationTask?.cancel()
    }
}

private extension OfflineTranscriptionTabViewModel {
    static let supportedAudioExtensions: Set<String> = ["wav", "m4a", "mp3", "aac"]

    static func availableDescriptors(
        from modelService: ActiveModelService,
        ensuringSelectionID selectionID: String
    ) -> [ModelDescriptor] {
        var ordered: [ModelDescriptor] = modelService.visibleModels(kind: .asr)
        if ordered.isEmpty {
            ordered = modelService.enabledModels(kind: .asr)
        }
        if let selected = modelService.registeredModels.first(where: {
            $0.engine.capabilities.contains(.asr) && $0.id == selectionID
        }) {
            ordered.insert(selected, at: 0)
        }

        var seenIDs: Set<String> = []
        return ordered.filter { descriptor in
            seenIDs.insert(descriptor.id).inserted
        }
    }

    func observeJobs() async {
        guard let coordinator else {
            return
        }

        let stream = await coordinator.snapshotStream()
        for await snapshot in stream {
            guard !Task.isCancelled else {
                break
            }

            jobs = Self.sortedJobs(snapshot)
            if let selectedCompletedJobID,
               jobs.contains(where: { $0.id == selectedCompletedJobID }) == false {
                closeSelectedCompletedJob()
            }
        }
    }

    func enqueueSupportedAudioURLs(_ urls: [URL]) async {
        guard let coordinator else {
            return
        }

        for url in urls where Self.isSupportedAudioURL(url) {
            _ = await coordinator.enqueueFile(
                url: url,
                descriptorID: selectedDescriptorID,
                diarize: diarizationEnabled
            )
        }
    }

    static func sortedJobs(
        _ jobs: [OfflineTranscriptionCoordinator.Job]
    ) -> [OfflineTranscriptionCoordinator.Job] {
        jobs.sorted { lhs, rhs in
            if lhs.enqueuedAt != rhs.enqueuedAt {
                return lhs.enqueuedAt > rhs.enqueuedAt
            }
            return lhs.id.uuidString > rhs.id.uuidString
        }
    }

    static func isSupportedAudioURL(_ url: URL) -> Bool {
        supportedAudioExtensions.contains(url.pathExtension.lowercased())
    }
}
