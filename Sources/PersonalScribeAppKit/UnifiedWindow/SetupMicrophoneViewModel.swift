import Foundation
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession

enum SetupPracticeSessionEvent: Equatable {
    case captureStarted(Int)
    case completed(Int)
}

@MainActor
final class SetupMicrophoneViewModel: ObservableObject {
    @Published private(set) var devices: [AudioInputDevice] = []
    @Published private(set) var selectedDeviceID: String?
    @Published private(set) var level: Float = 0
    @Published private(set) var isMonitoring = false
    @Published private(set) var sessionState: SessionState
    @Published private(set) var recordingElapsedSeconds: Int
    @Published private(set) var practiceSessionEvent: SetupPracticeSessionEvent?

    private let inputDeviceProvider: any AudioInputDeviceProviding
    private let levelMonitor: any AudioLevelMonitoring
    private let currentSessionSnapshot: @Sendable () async -> SessionSnapshot
    private let sessionSnapshots: @Sendable () async -> AsyncStream<SessionSnapshot>
    private var levelTask: Task<Void, Never>?
    private var sessionTask: Task<Void, Never>?
    private var isVisible = false
    private var isPracticeVisible = false
    private var isStarting = false
    private var monitorGeneration = 0
    private var latestSessionSnapshot: SessionSnapshot
    private var practiceCaptureWasSeen = false
    private var practiceEventSequence = 0

    init(
        inputDeviceProvider: any AudioInputDeviceProviding,
        levelMonitor: any AudioLevelMonitoring,
        initialSessionSnapshot: SessionSnapshot = SessionSnapshot(),
        currentSessionSnapshot: @escaping @Sendable () async -> SessionSnapshot = {
            SessionSnapshot()
        },
        sessionSnapshots: @escaping @Sendable () async -> AsyncStream<SessionSnapshot> = {
            AsyncStream { continuation in
                continuation.yield(SessionSnapshot())
                continuation.finish()
            }
        }
    ) {
        self.inputDeviceProvider = inputDeviceProvider
        self.levelMonitor = levelMonitor
        self.latestSessionSnapshot = initialSessionSnapshot
        self.sessionState = initialSessionSnapshot.sessionState
        self.recordingElapsedSeconds = Self.elapsedSeconds(in: initialSessionSnapshot)
        self.practiceSessionEvent = nil
        self.currentSessionSnapshot = currentSessionSnapshot
        self.sessionSnapshots = sessionSnapshots
    }

    isolated deinit {
        levelTask?.cancel()
        sessionTask?.cancel()
    }

    func appear() async {
        isVisible = true
        updateSessionObservation()
        devices = inputDeviceProvider.availableDevices()
        selectedDeviceID = inputDeviceProvider.effectiveDeviceID
        await applySessionSnapshot(await currentSessionSnapshot())
    }

    func disappear() async {
        isVisible = false
        updateSessionObservation()
        await stopMonitoring()
    }

    func windowDidHide() async {
        isVisible = false
        isPracticeVisible = false
        practiceCaptureWasSeen = false
        updateSessionObservation()
        if recordingElapsedSeconds != 0 {
            recordingElapsedSeconds = 0
        }
        await stopMonitoring()
    }

    func selectDevice(id: String?) async {
        let snapshot = await currentSessionSnapshot()
        updatePublishedSessionValues(from: snapshot)
        guard snapshot.sessionState.displayState == .idle else {
            selectedDeviceID = inputDeviceProvider.effectiveDeviceID
            await stopMonitoring()
            return
        }
        inputDeviceProvider.selectDevice(id: id)
        selectedDeviceID = inputDeviceProvider.effectiveDeviceID
        await stopMonitoring()
        if isVisible {
            await startMonitoring()
        }
    }

    var isRecording: Bool {
        switch sessionState.displayState {
        case .capturing, .holdRecording:
            true
        case .idle, .paused, .transcribing, .completed, .shortExit, .error:
            false
        }
    }

    func setPracticeVisible(_ visible: Bool) async {
        isPracticeVisible = visible
        if !visible {
            practiceCaptureWasSeen = false
            updateSessionObservation()
        } else {
            let snapshot = await currentSessionSnapshot()
            guard isPracticeVisible else { return }
            await applySessionSnapshot(snapshot, emitsPracticeEvents: false)
            updateSessionObservation()
        }
        if visible, sessionState != latestSessionSnapshot.sessionState {
            sessionState = latestSessionSnapshot.sessionState
        }
        let elapsed = visible ? Self.elapsedSeconds(in: latestSessionSnapshot) : 0
        if recordingElapsedSeconds != elapsed {
            recordingElapsedSeconds = elapsed
        }
    }

    private var isSessionIdle: Bool {
        latestSessionSnapshot.sessionState.displayState == .idle
    }

    private func updateSessionObservation() {
        guard isVisible || isPracticeVisible else {
            sessionTask?.cancel()
            sessionTask = nil
            return
        }
        guard sessionTask == nil else { return }
        sessionTask = Task { @MainActor [weak self, sessionSnapshots] in
            let stream = await sessionSnapshots()
            for await snapshot in stream {
                guard let self, !Task.isCancelled else { return }
                await self.applySessionSnapshot(snapshot, emitsPracticeEvents: true)
            }
        }
    }

    private func applySessionSnapshot(
        _ snapshot: SessionSnapshot,
        emitsPracticeEvents: Bool = false
    ) async {
        let wasIdle = isSessionIdle
        updatePracticeSessionEvent(from: snapshot, emitsEvent: emitsPracticeEvents)
        updatePublishedSessionValues(from: snapshot)
        guard isSessionIdle else {
            if wasIdle || isMonitoring || isStarting {
                await stopMonitoring()
            }
            return
        }
        if !wasIdle {
            await stopMonitoring()
        }
        if isVisible {
            await startMonitoring()
        }
    }

    private func stopMonitoring() async {
        monitorGeneration += 1
        isStarting = false
        levelTask?.cancel()
        levelTask = nil
        await levelMonitor.stop()
        if isMonitoring {
            isMonitoring = false
        }
        if level != 0 {
            level = 0
        }
    }

    private func startMonitoring() async {
        guard isVisible, isSessionIdle, !isMonitoring, !isStarting else { return }
        isStarting = true
        monitorGeneration += 1
        let generation = monitorGeneration
        do {
            let stream = try await levelMonitor.start()
            guard generation == monitorGeneration, isVisible, isSessionIdle else {
                if !isStarting && !isMonitoring {
                    await levelMonitor.stop()
                }
                return
            }
            isStarting = false
            isMonitoring = true
            levelTask = Task { @MainActor [weak self] in
                for await level in stream {
                    guard !Task.isCancelled else { return }
                    guard let self, generation == self.monitorGeneration else { return }
                    if self.level != level {
                        self.level = level
                    }
                }
                guard let self, generation == self.monitorGeneration else { return }
                if self.isMonitoring {
                    self.isMonitoring = false
                }
                if self.level != 0 {
                    self.level = 0
                }
            }
        } catch {
            guard generation == monitorGeneration else { return }
            isStarting = false
            isMonitoring = false
            level = 0
        }
    }

    private func updatePublishedSessionValues(from snapshot: SessionSnapshot) {
        latestSessionSnapshot = snapshot
        if (isVisible || isPracticeVisible), sessionState != snapshot.sessionState {
            sessionState = snapshot.sessionState
        }
        if isPracticeVisible {
            let elapsed = Self.elapsedSeconds(in: snapshot)
            if recordingElapsedSeconds != elapsed {
                recordingElapsedSeconds = elapsed
            }
        }
    }

    private func updatePracticeSessionEvent(
        from snapshot: SessionSnapshot,
        emitsEvent: Bool
    ) {
        guard isPracticeVisible else {
            practiceCaptureWasSeen = false
            return
        }
        guard emitsEvent else {
            practiceCaptureWasSeen = Self.isCaptureInProgress(snapshot.sessionState)
            return
        }
        if Self.isCaptureInProgress(snapshot.sessionState) {
            if !practiceCaptureWasSeen {
                practiceCaptureWasSeen = true
                publishPracticeEvent { .captureStarted($0) }
            }
            return
        }
        guard practiceCaptureWasSeen, snapshot.sessionState == .completed else { return }
        practiceCaptureWasSeen = false
        guard let text = snapshot.lastCompletedResult?.text,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        publishPracticeEvent { .completed($0) }
    }

    private func publishPracticeEvent(
        _ event: (Int) -> SetupPracticeSessionEvent
    ) {
        practiceEventSequence += 1
        practiceSessionEvent = event(practiceEventSequence)
    }

    private static func isCaptureInProgress(_ state: SessionState) -> Bool {
        switch state.displayState {
        case .capturing, .holdRecording, .paused:
            true
        case .idle, .transcribing, .completed, .shortExit, .error:
            false
        }
    }

    private static func elapsedSeconds(in snapshot: SessionSnapshot) -> Int {
        guard let duration = snapshot.recordingDuration else { return 0 }
        return max(0, Int(duration.components.seconds))
    }
}
