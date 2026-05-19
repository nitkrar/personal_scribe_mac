import Foundation
import PersonalScribeCore

@MainActor
final class RetranscribeLastRecordingAction {
    var onAvailabilityChange: (@MainActor () -> Void)?
    private(set) var isEnabled = false

    private let transcriptReader: any TranscriptReading
    private let toastBroadcaster: any ToastPosting
    private let runner: any RetranscriptionPerforming
    private let notificationCenter: NotificationCenter
    private var transcriptCommitObservation: NSObjectProtocol?

    init(
        transcriptReader: any TranscriptReading,
        coordinator: any OfflineTranscriptionCoordinating,
        clipboardWriter: @escaping CopyLastTranscriptAction.ClipboardWriter,
        toastBroadcaster: any ToastPosting,
        notificationCenter: NotificationCenter = .default
    ) {
        self.transcriptReader = transcriptReader
        self.toastBroadcaster = toastBroadcaster
        self.runner = RetranscriptionRunner(
            transcriptReader: transcriptReader,
            coordinator: coordinator,
            clipboardWriter: clipboardWriter,
            toastBroadcaster: toastBroadcaster
        )
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

        await runner.perform(sourceFilename: sourceFilename)
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
