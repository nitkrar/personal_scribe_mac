import Combine
import Foundation

@MainActor
public final class AppStore: ObservableObject {
    public static let doneVisibilityDuration: Duration = .milliseconds(1_000)
    public static let errorVisibilityDuration: Duration = .milliseconds(1_500)
    public static let recordingDurationTickInterval: Duration = .milliseconds(250)

    @Published public private(set) var snapshot: AppStoreSnapshot

    private let session: any AppStoreSessionProviding
    private let permissions: any PermissionService
    /// #078.36 / L21 — `WorkflowModeRegistry` replaces the deleted
    /// `AppStoreActiveModeProviding` protocol. AppStore consumes the
    /// registry directly (no re-pointing); the registry's
    /// `activeModeStream()` feeds `snapshot.activeMode`.
    private let workflowModeRegistry: WorkflowModeRegistry
    private let visibilityModeSource: any AppStoreVisibilityModeProviding
    private let clock: any AppStoreClock
    private let permissionSnapshotProvider: @MainActor @Sendable () -> [Permission: PermissionStatus]
    private let permissionObserverInstaller:
        @MainActor @Sendable (@escaping @MainActor ([Permission: PermissionStatus]) -> Void) -> AnyCancellable

    private var currentVisibilityMode: AppStoreVisibilityMode
    private var hasStarted = false
    private var sessionObservationTask: Task<Void, Never>?
    private var permissionsObservationTask: Task<Void, Never>?
    private var modeObservationTask: Task<Void, Never>?
    private var pillTransitionTask: Task<Void, Never>?
    private var recordingDurationTask: Task<Void, Never>?
    private var permissionObservationCancellable: AnyCancellable?

    public init<Permissions: PermissionService>(
        session: any AppStoreSessionProviding,
        permissions: Permissions,
        workflowModeRegistry: WorkflowModeRegistry,
        visibilityModeSource: any AppStoreVisibilityModeProviding,
        clock: any AppStoreClock = LiveAppStoreClock()
    ) {
        self.session = session
        self.permissions = permissions
        self.workflowModeRegistry = workflowModeRegistry
        self.visibilityModeSource = visibilityModeSource
        self.clock = clock
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
            activeMode: workflowModeRegistry.activeMode,
            pillVisibility: Self.derivePillVisibility(
                mode: initialVisibilityMode,
                sessionState: initialSession.sessionState,
                progress: initialSession.modelDownloadProgress
            ),
            lastTranscriptionResult: nil,
            currentRecordingDuration: nil
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
                    for await activeMode in workflowModeRegistry.activeModeStream() {
                        guard let self else { return }
                        await self.handleActiveModeChange(activeMode)
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

        if !previousState.isRecording && newState.isRecording {
            startRecordingDurationLoop()
        } else if previousState.isRecording && !newState.isRecording {
            stopRecordingDurationLoop()
        }

        if newState == .completed {
            guard previousState != .completed else {
                return
            }

            updateSnapshot { snapshot in
                snapshot.lastTranscriptionResult = newSession.lastCompletedResult
                snapshot.pillVisibility = .done
            }
            schedulePillTransition(after: Self.doneVisibilityDuration)
            return
        }

        if case .error(let error) = newState {
            guard previousState != newState else {
                return
            }

            updateSnapshot { snapshot in
                snapshot.pillVisibility = .error(message: Self.pillMessage(for: error))
            }
            schedulePillTransition(after: Self.errorVisibilityDuration)
            return
        }

        // `#075`: `.shortExit` flips pill straight to idle — no chip,
        // no message. The short hold itself is the user-facing signal;
        // the pill returning to idle confirms the pipeline exited.
        // `rederivePillVisibility()` routes through `derivePillVisibility`,
        // which maps `.shortExit` to `idleVisibility`.
        cancelPillTransition()
        rederivePillVisibility()
    }

    private func handleActiveModeChange(_ activeMode: WorkflowMode) {
        updateSnapshot { snapshot in
            snapshot.activeMode = activeMode
        }
    }

    private func handleVisibilityModeChange(_ visibilityMode: AppStoreVisibilityMode) {
        guard visibilityMode != currentVisibilityMode else { return }
        currentVisibilityMode = visibilityMode
        cancelPillTransition()
        rederivePillVisibility()
    }

    private func startRecordingDurationLoop() {
        recordingDurationTask?.cancel()

        let recordingStart = clock.now()
        let clock = self.clock
        updateSnapshot { snapshot in
            snapshot.currentRecordingDuration = .zero
        }

        recordingDurationTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await clock.sleep(for: Self.recordingDurationTickInterval)
                } catch {
                    return
                }

                guard !Task.isCancelled, let self else {
                    return
                }

                self.updateRecordingDuration(clock.now() - recordingStart)
            }
        }
    }

    private func stopRecordingDurationLoop() {
        recordingDurationTask?.cancel()
        recordingDurationTask = nil
        updateSnapshot { snapshot in
            snapshot.currentRecordingDuration = nil
        }
    }

    private func updateRecordingDuration(_ duration: Duration) {
        updateSnapshot { snapshot in
            snapshot.currentRecordingDuration = duration
        }
    }

    private func schedulePillTransition(after duration: Duration) {
        pillTransitionTask?.cancel()
        let clock = self.clock
        pillTransitionTask = Task { [weak self] in
            do {
                try await clock.sleep(for: duration)
            } catch {
                return
            }

            guard !Task.isCancelled, let self else {
                return
            }

            self.completePillTransition()
        }
    }

    private func completePillTransition() {
        pillTransitionTask = nil
        rederivePillVisibility()
    }

    private func cancelPillTransition() {
        pillTransitionTask?.cancel()
        pillTransitionTask = nil
    }

    private func refreshStaticInputs() {
        currentVisibilityMode = visibilityModeSource.currentVisibilityMode()

        updateSnapshot { snapshot in
            snapshot.permissions = permissionSnapshotProvider()
            snapshot.activeMode = workflowModeRegistry.activeMode
        }

        rederivePillVisibility()
    }

    private func rederivePillVisibility() {
        let visibility = Self.derivePillVisibility(
            mode: currentVisibilityMode,
            sessionState: snapshot.session.sessionState,
            progress: snapshot.modelDownloadProgress
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
        progress: ModelDownloadProgress?
    ) -> PillVisibilityState {
        if sessionState.isHoldRecording {
            return .holdToRecord
        }

        if sessionState.isRecording {
            return .recording
        }

        if sessionState.isTranscribing {
            return transcribingVisibility(progress: progress)
        }

        if case .error = sessionState {
            return idleVisibility(for: mode, progress: progress)
        }

        if mode == .hidden {
            return .hidden
        }

        switch sessionState {
        case .idle:
            return idleVisibility(for: mode, progress: progress)
        case .capturing:
            return .recording
        case .holdRecording:
            return .holdToRecord
        case .transcribing:
            return transcribingVisibility(progress: progress)
        case .completed, .shortExit:
            return idleVisibility(for: mode, progress: progress)
        case .error:
            return .hidden
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
        case .autoShow, .hidden:
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

    private static func pillMessage(for error: PersonalScribeError) -> String {
        switch error {
        case .transcriptionFailure:
            return "Transcription failed"
        case .micPermissionDenied:
            return "Microphone permission needed"
        case .audioEngineFailure, .resampleFailure:
            return "Recording failed"
        case .modelLoadFailure:
            return "Model unavailable"
        case .cancelled:
            return "Cancelled"
        case .invalidState:
            return "Session error"
        case .invalidActiveMode:
            return "Selected mode is invalid"
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

public struct LiveAppStoreClock: AppStoreClock {
    public init() {}
    private let clock = ContinuousClock()
    private let reference = ContinuousClock().now

    public func now() -> Duration {
        reference.duration(to: clock.now)
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}
