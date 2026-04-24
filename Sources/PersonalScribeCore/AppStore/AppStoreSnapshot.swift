import Foundation

public struct AppStoreSnapshot: Sendable, Equatable {
    public var session: SessionSnapshot
    public var permissions: [Permission: PermissionStatus]
    public var activeMode: ModeDescriptor?
    public var pillVisibility: PillVisibilityState
    public var lastTranscriptionResult: TranscriptionResult?
    public var currentRecordingDuration: Duration?

    public init(
        session: SessionSnapshot,
        permissions: [Permission: PermissionStatus],
        activeMode: ModeDescriptor?,
        pillVisibility: PillVisibilityState,
        lastTranscriptionResult: TranscriptionResult?,
        currentRecordingDuration: Duration?
    ) {
        self.session = session
        self.permissions = permissions
        self.activeMode = activeMode
        self.pillVisibility = pillVisibility
        self.lastTranscriptionResult = lastTranscriptionResult
        self.currentRecordingDuration = currentRecordingDuration
    }

    public var sessionState: SessionState {
        switch session.sessionState {
        case .completed, .shortExit:
            return .idle
        case .idle, .recording, .holdRecording, .transcribing, .error:
            return session.sessionState
        }
    }

    public var modelDownloadProgress: ModelDownloadProgress? {
        guard let progress = session.modelDownloadProgress else {
            return nil
        }

        switch progress.phase {
        case .idle, .finished:
            return nil
        case .downloading, .loading:
            return progress
        }
    }

}
