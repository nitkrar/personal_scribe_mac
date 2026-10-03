import Foundation

public struct AppStoreSnapshot: Sendable, Equatable {
    public var session: SessionSnapshot
    public var permissions: [Permission: PermissionStatus]
    public var activeMode: WorkflowMode?
    public var pillVisibility: PillVisibilityState
    public var lastTranscriptionResult: TranscriptionResult?

    public init(
        session: SessionSnapshot,
        permissions: [Permission: PermissionStatus],
        activeMode: WorkflowMode?,
        pillVisibility: PillVisibilityState,
        lastTranscriptionResult: TranscriptionResult?
    ) {
        self.session = session
        self.permissions = permissions
        self.activeMode = activeMode
        self.pillVisibility = pillVisibility
        self.lastTranscriptionResult = lastTranscriptionResult
    }

    public var sessionState: SessionState {
        session.sessionState.displayState
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
