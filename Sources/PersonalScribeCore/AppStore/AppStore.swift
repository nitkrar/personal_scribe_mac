import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
    @Published public private(set) var snapshot: AppStoreSnapshot

    private let session: any AppStoreSessionProviding
    private let permissions: any PermissionService
    /// #078.36 / L21 — `WorkflowModeRegistry` replaces the deleted
    /// `AppStoreActiveModeProviding` protocol. AppStore consumes the
    /// registry directly (no re-pointing); the registry's
    /// `currentModeStream()` feeds `snapshot.activeMode` (#089: DTO
    /// field name preserved; source is `currentMode`).
    private let workflowModeRegistry: WorkflowModeRegistry
    private let visibilityModeSource: any AppStoreVisibilityModeProviding
    private let permissionSnapshotProvider: @MainActor @Sendable () -> [Permission: PermissionStatus]
    private let permissionObserverInstaller:
        @MainActor @Sendable (@escaping @MainActor ([Permission: PermissionStatus]) -> Void) -> AnyCancellable

    private var currentVisibilityMode: AppStoreVisibilityMode
    private var hasStarted = false
    private var sessionObservationTask: Task<Void, Never>?
    private var permissionsObservationTask: Task<Void, Never>?
    private var modeObservationTask: Task<Void, Never>?
    private var permissionObservationCancellable: AnyCancellable?

    public init<Permissions: PermissionService>(
        session: any AppStoreSessionProviding,
        permissions: Permissions,
        workflowModeRegistry: WorkflowModeRegistry,
        visibilityModeSource: any AppStoreVisibilityModeProviding
    ) {
        self.session = session
        self.permissions = permissions
        self.workflowModeRegistry = workflowModeRegistry
        self.visibilityModeSource = visibilityModeSource
        self.permissionSnapshotProvider = {
            permissions.statusSnapshot()
        }
        self.permissionObserverInstaller = { onChange in
            permissions.objectWillChange.sink { _ in
                Task { @MainActor in
                    onChange(permissions.statusSnapshot())
                }
            }
        }

        let initialVisibilityMode = visibilityModeSource.currentVisibilityMode()
        let initialSession = SessionSnapshot()
        currentVisibilityMode = initialVisibilityMode
        snapshot = AppStoreSnapshot(
            session: initialSession,
            permissions: permissions.statusSnapshot(),
            activeMode: workflowModeRegistry.currentMode,
            pillVisibility: Self.derivePillVisibility(
                mode: initialVisibilityMode,
                sessionState: initialSession.sessionState,
                recordingDuration: initialSession.recordingDuration,
                progress: initialSession.modelDownloadProgress,
                cancelledCaptureResumable: initialSession.cancelledCaptureResumable
            ),
            lastTranscriptionResult: nil
        )
    }

    public func start() {
        guard !hasStarted else {
            return
        }

        hasStarted = true
        refreshStaticInputs()

        let session = self.session
        let workflowModeRegistry = self.workflowModeRegistry
        let visibilityModeSource = self.visibilityModeSource

        sessionObservationTask = Task { [weak self] in
            for await sessionSnapshot in session.snapshotStream() {
                guard let self else { return }
                self.handleSessionSnapshotChange(sessionSnapshot)
            }
        }
        permissionsObservationTask = Task { [weak self] in
            guard let self else { return }
            let stream = self.makePermissionStatusStream()
            for await statuses in stream {
                self.updateSnapshot { snapshot in
                    snapshot.permissions = statuses
                }
            }
        }
        modeObservationTask = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    for await currentMode in workflowModeRegistry.currentModeStream() {
                        guard let self else { return }
                        await self.handleCurrentModeChange(currentMode)
                    }
                }

                group.addTask { [weak self] in
                    for await visibilityMode in visibilityModeSource.visibilityModeStream() {
                        guard let self else { return }
                        await self.handleVisibilityModeChange(visibilityMode)
                    }
                }

                await group.waitForAll()
            }
        }
    }

    private func handleSessionSnapshotChange(_ newSession: SessionSnapshot) {
        let previousState = snapshot.session.sessionState
        let newState = newSession.sessionState

        updateSnapshot { snapshot in
            snapshot.session = newSession
        }

        if newState == .completed {
            guard previousState != .completed else {
                return
            }

            updateSnapshot { snapshot in
                snapshot.lastTranscriptionResult = newSession.lastCompletedResult
            }
        }

        // `#075`: `.shortExit` flips pill straight to idle — no chip,
        // no message. The short hold itself is the user-facing signal;
        // the pill returning to idle confirms the pipeline exited.
        // `rederivePillVisibility()` routes through `derivePillVisibility`,
        // which maps `.shortExit` to `idleVisibility`.
        rederivePillVisibility()
    }

    private func handleCurrentModeChange(_ currentMode: WorkflowMode) {
        updateSnapshot { snapshot in
            snapshot.activeMode = currentMode
        }
    }

    private func handleVisibilityModeChange(_ visibilityMode: AppStoreVisibilityMode) {
        guard visibilityMode != currentVisibilityMode else { return }
        currentVisibilityMode = visibilityMode
        rederivePillVisibility()
    }

    private func refreshStaticInputs() {
        currentVisibilityMode = visibilityModeSource.currentVisibilityMode()

        updateSnapshot { snapshot in
            snapshot.permissions = permissionSnapshotProvider()
            snapshot.activeMode = workflowModeRegistry.currentMode
        }

        rederivePillVisibility()
    }

    private func rederivePillVisibility() {
        let visibility = Self.derivePillVisibility(
            mode: currentVisibilityMode,
            sessionState: snapshot.session.sessionState,
            recordingDuration: snapshot.session.recordingDuration,
            progress: snapshot.modelDownloadProgress,
            cancelledCaptureResumable: snapshot.session.cancelledCaptureResumable
        )

        updateSnapshot { snapshot in
            snapshot.pillVisibility = visibility
        }
    }

    private func makePermissionStatusStream() -> AsyncStream<[Permission: PermissionStatus]> {
        AsyncStream { continuation in
            continuation.yield(permissionSnapshotProvider())
            permissionObservationCancellable = permissionObserverInstaller { statuses in
                continuation.yield(statuses)
            }
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.permissionObservationCancellable = nil
                }
            }
        }
    }

    private func updateSnapshot(_ mutate: (inout AppStoreSnapshot) -> Void) {
        var nextSnapshot = snapshot
        mutate(&nextSnapshot)
        snapshot = nextSnapshot
    }

    private static func derivePillVisibility(
        mode: AppStoreVisibilityMode,
        sessionState: SessionState,
        recordingDuration: Duration?,
        progress: ModelDownloadProgress?,
        cancelledCaptureResumable: Bool
    ) -> PillVisibilityState {
        if cancelledCaptureResumable {
            return .cancelled
        }

        if sessionState.isHoldRecording {
            return .holdToRecord
        }

        if sessionState.isRecording {
            return .recording
        }

        if sessionState == .paused {
            return .paused(
                elapsedSeconds: Int(recordingDuration?.components.seconds ?? 0)
            )
        }

        if sessionState.isTranscribing {
            return transcribingVisibility(progress: progress)
        }

        if case .error = sessionState {
            return idleVisibility(for: mode, progress: progress)
        }

        switch sessionState {
        case .idle:
            return idleVisibility(for: mode, progress: progress)
        case .capturing:
            return .recording
        case .holdRecording:
            return .holdToRecord
        case .paused:
            return .paused(
                elapsedSeconds: Int(recordingDuration?.components.seconds ?? 0)
            )
        case .transcribing:
            return transcribingVisibility(progress: progress)
        case .completed, .shortExit, .error:
            return idleVisibility(for: mode, progress: progress)
        }
    }

    private static func idleVisibility(
        for mode: AppStoreVisibilityMode,
        progress: ModelDownloadProgress?
    ) -> PillVisibilityState {
        if let progress {
            switch progress.phase {
            case .idle, .finished:
                break
            case .downloading:
                return .downloading(fractionCompleted: progress.fractionCompleted)
            case .loading:
                return .loading
            }
        }

        switch mode {
        case .alwaysOn:
            return .idle
        case .autoShow:
            return .hidden
        }
    }

    private static func transcribingVisibility(
        progress: ModelDownloadProgress?
    ) -> PillVisibilityState {
        guard let progress else {
            return .transcribing
        }

        switch progress.phase {
        case .idle, .finished:
            return .transcribing
        case .downloading:
            return .downloading(fractionCompleted: progress.fractionCompleted)
        case .loading:
            return .loading
        }
    }
}

private extension SessionState {
    var isIdle: Bool {
        if case .idle = self {
            return true
        }

        return false
    }

    var isRecording: Bool {
        if case .capturing = self {
            return true
        }

        return false
    }

    var isHoldRecording: Bool {
        if case .holdRecording = self {
            return true
        }

        return false
    }

    var isTranscribing: Bool {
        if case .transcribing = self {
            return true
        }

        return false
    }
}
