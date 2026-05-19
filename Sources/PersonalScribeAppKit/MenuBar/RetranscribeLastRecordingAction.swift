import Foundation
import PersonalScribeCore

@MainActor
final class RetranscribeLastRecordingAction {
    typealias ClipboardWriter = CopyLastTranscriptAction.ClipboardWriter

    var onAvailabilityChange: (@MainActor () -> Void)?
    private(set) var isEnabled = false

    private let transcriptReader: any TranscriptReading
    private let coordinator: any OfflineTranscriptionCoordinating
    private let clipboardWriter: ClipboardWriter
    private let toastBroadcaster: any ToastPosting
    private let notificationCenter: NotificationCenter
    private var transcriptCommitObservation: NSObjectProtocol?

    init(
        transcriptReader: any TranscriptReading,
        coordinator: any OfflineTranscriptionCoordinating,
        clipboardWriter: @escaping ClipboardWriter,
        toastBroadcaster: any ToastPosting,
        notificationCenter: NotificationCenter = .default
    ) {
        self.transcriptReader = transcriptReader
        self.coordinator = coordinator
        self.clipboardWriter = clipboardWriter
        self.toastBroadcaster = toastBroadcaster
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
    }

    isolated deinit {
        if let transcriptCommitObservation {
            notificationCenter.removeObserver(transcriptCommitObservation)
        }
    }

    func perform() async {
        guard let sourceEntry = await transcriptReader.mostRecentEntryWithAudio(),
              let sourceFilename = sourceEntry.audioFilename,
              !sourceFilename.isEmpty else {
            toastBroadcaster.post(
                ToastBroadcaster.Message(
                    text: "No recordings available to re-transcribe"
                )
            )
            await refreshAvailability()
            return
        }

        let jobID = await coordinator.reTranscribe(sourceFilename: sourceFilename)
        guard let terminalStatus = await observeTerminalStatus(for: jobID) else {
            return
        }

        switch terminalStatus {
        case .completed(let transcriptID):
            let entries = await transcriptReader.all()
            guard let transcriptText = entries.first(where: { $0.id == transcriptID })?.text else {
                toastBroadcaster.post(
                    ToastBroadcaster.Message(text: "Re-transcription failed")
                )
                return
            }

            clipboardWriter(transcriptText)
            toastBroadcaster.post(
                ToastBroadcaster.Message(text: "Re-transcribed → clipboard")
            )
        case .failed(let reason):
            switch reason {
            case .audioMissing:
                toastBroadcaster.post(
                    ToastBroadcaster.Message(
                        text: "Audio file no longer available — link removed"
                    )
                )
            case .modelNotAvailable,
                 .conversionFailed,
                 .transcriptionFailed,
                 .other:
                toastBroadcaster.post(
                    ToastBroadcaster.Message(text: "Re-transcription failed")
                )
            }
        case .cancelled, .queued, .inFlight:
            return
        }
    }

    func refreshAvailability() async {
        let nextValue = await transcriptReader.mostRecentEntryWithAudio() != nil
        guard nextValue != isEnabled else {
            return
        }

        isEnabled = nextValue
        onAvailabilityChange?()
    }
}

private extension RetranscribeLastRecordingAction {
    func observeTerminalStatus(
        for jobID: UUID
    ) async -> OfflineTranscriptionCoordinator.JobStatus? {
        let stream = await coordinator.snapshotStream()
        for await jobs in stream {
            guard let job = jobs.first(where: { $0.id == jobID }) else {
                continue
            }

            switch job.status {
            case .completed, .failed, .cancelled:
                return job.status
            case .queued, .inFlight:
                continue
            }
        }

        return nil
    }
}
