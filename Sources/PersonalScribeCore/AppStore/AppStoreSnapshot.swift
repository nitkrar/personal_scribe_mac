import Foundation

public struct AppStoreSnapshot: Sendable, Equatable {
    public var sessionState: SessionState
    public var permissions: [Permission: PermissionStatus]
    public var activeMode: ModeDescriptor?
    public var modelDownloadProgress: ModelDownloadProgress?
    public var pillVisibility: PillVisibilityState
    public var lastTranscriptionResult: TranscriptionResult?
    public var currentRecordingDuration: Duration?

    public init(
        sessionState: SessionState,
        permissions: [Permission: PermissionStatus],
        activeMode: ModeDescriptor?,
        modelDownloadProgress: ModelDownloadProgress?,
        pillVisibility: PillVisibilityState,
        lastTranscriptionResult: TranscriptionResult?,
        currentRecordingDuration: Duration?
    ) {
        self.sessionState = sessionState
        self.permissions = permissions
        self.activeMode = activeMode
        self.modelDownloadProgress = modelDownloadProgress
        self.pillVisibility = pillVisibility
        self.lastTranscriptionResult = lastTranscriptionResult
        self.currentRecordingDuration = currentRecordingDuration
    }
}
