import Combine
import Foundation
import PersonalScribeCore
import PersonalScribeSession

@MainActor
final class OfflineRetranscriptionAction: ObservableObject {
    typealias ClipboardWriter = @MainActor @Sendable (String) -> Void

    @Published private(set) var isAvailable = false
    @Published private(set) var busySourceFilenames: Set<String> = []

    private let transcriptReader: any TranscriptReading
    private let coordinator: any OfflineTranscriptionJobManaging
    private let toastBroadcaster: ToastBroadcaster
    private let clipboardWriter: ClipboardWriter
    private let notificationCenter: NotificationCenter

    private var transcriptCommitObservation: NSObjectProtocol?
    private var snapshotObservationTask: Task<Void, Never>?
    private var jobObservationTasks: [UUID: Task<Void, Never>] = [:]

    init(
        transcriptReader: any TranscriptReading,
        coordinator: any OfflineTranscriptionJobManaging,
        toastBroadcaster: ToastBroadcaster,
        clipboardWriter: @escaping ClipboardWriter,
        notificationCenter: NotificationCenter = .default
    ) {
        self.transcriptReader = transcriptReader
        self.coordinator = coordinator
        self.toastBroadcaster = toastBroadcaster
        self.clipboardWriter = clipboardWriter
        self.notificationCenter = notificationCenter

        transcriptCommitObservation = notificationCenter.addObserver(
            forName: MetricsNotification.transcriptCommit,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshAvailability()
            }
        }

        Task { @MainActor [weak self] in
            await self?.refreshAvailability()
        }
        snapshotObservationTask = Task { @MainActor [weak self] in
            await self?.observeCoordinatorSnapshots()
        }
    }

    func refreshAvailability() async {
        let entry = await transcriptReader.mostRecentEntryWithAudio()
        isAvailable = !(entry?.audioFilename?.isEmpty ?? true)
    }

    func performLatestRecordingRetranscription() async {
        guard let entry = await transcriptReader.mostRecentEntryWithAudio(),
              let sourceFilename = entry.audioFilename,
              !sourceFilename.isEmpty else {
            toastBroadcaster.post(.info("No recordings available to re-transcribe"))
            isAvailable = false
            return
        }

        await performRetranscription(sourceFilename: sourceFilename)
    }

    func performRetranscription(sourceFilename: String) async {
        guard !sourceFilename.isEmpty else {
            return
        }

        let jobID = await coordinator.reTranscribe(sourceFilename: sourceFilename)
        guard jobObservationTasks[jobID] == nil else {
            return
        }

        jobObservationTasks[jobID] = Task { @MainActor [weak self] in
            await self?.observeJob(id: jobID)
        }
    }

    isolated deinit {
        if let transcriptCommitObservation {
            notificationCenter.removeObserver(transcriptCommitObservation)
        }
        snapshotObservationTask?.cancel()
        for task in jobObservationTasks.values {
            task.cancel()
        }
    }
}

private extension OfflineRetranscriptionAction {
    func observeCoordinatorSnapshots() async {
        let stream = await coordinator.snapshotStream()
        for await jobs in stream {
            guard !Task.isCancelled else {
                return
            }
            busySourceFilenames = Set(jobs.compactMap { job in
                switch job.status {
                case .inFlight:
                    return job.sourceFilename
                case .queued, .completed, .failed, .cancelled:
                    return nil
                }
            })
        }
    }

    func observeJob(id: UUID) async {
        defer {
            jobObservationTasks[id]?.cancel()
            jobObservationTasks[id] = nil
        }

        let stream = await coordinator.snapshotStream()
        for await jobs in stream {
            guard !Task.isCancelled else {
                return
            }
            guard let job = jobs.first(where: { $0.id == id }) else {
                continue
            }

            switch job.status {
            case .completed(let transcriptID):
                await handleCompletedRetranscription(transcriptID: transcriptID)
                return
            case .failed(let reason):
                handleFailedRetranscription(reason: reason)
                return
            case .cancelled:
                return
            case .queued, .inFlight:
                continue
            }
        }
    }

    func handleCompletedRetranscription(transcriptID: UUID) async {
        let entries = await transcriptReader.all()
        guard let entry = entries.first(where: { $0.id == transcriptID }) else {
            toastBroadcaster.post(.error("Re-transcription failed"))
            return
        }

        clipboardWriter(entry.text)
        toastBroadcaster.post(.success("Re-transcribed → clipboard"))
    }

    func handleFailedRetranscription(reason: OfflineTranscriptionCoordinator.FailureReason) {
        switch reason {
        case .audioMissing:
            toastBroadcaster.post(.error("Audio file no longer available — link removed"))
        case .modelNotAvailable,
             .conversionFailed,
             .transcriptionFailed,
             .other:
            toastBroadcaster.post(.error("Re-transcription failed"))
        }
    }
}
