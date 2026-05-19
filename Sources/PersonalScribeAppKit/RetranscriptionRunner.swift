import Foundation
import PersonalScribeCore

protocol RetranscriptionPerforming: Sendable {
    func perform(sourceFilename: String) async
}

@MainActor
final class RetranscriptionRunner: RetranscriptionPerforming {
    typealias ClipboardWriter = CopyLastTranscriptAction.ClipboardWriter

    private let transcriptReader: any TranscriptReading
    private let coordinator: any OfflineTranscriptionCoordinating
    private let clipboardWriter: ClipboardWriter
    private let toastBroadcaster: any ToastPosting

    init(
        transcriptReader: any TranscriptReading,
        coordinator: any OfflineTranscriptionCoordinating,
        clipboardWriter: @escaping ClipboardWriter,
        toastBroadcaster: any ToastPosting
    ) {
        self.transcriptReader = transcriptReader
        self.coordinator = coordinator
        self.clipboardWriter = clipboardWriter
        self.toastBroadcaster = toastBroadcaster
    }

    func perform(sourceFilename: String) async {
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
}

private extension RetranscriptionRunner {
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
