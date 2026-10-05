import Foundation
import Combine
import XCTest
import PersonalScribeAudio
import PersonalScribeCore
import PersonalScribeSession
@testable import PersonalScribeAppKit

@MainActor
final class SetupMicrophoneViewModelTests: XCTestCase {
    func testAppearLoadsDevicesAndStartsStandaloneMonitor() async {
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor
        )

        await viewModel.appear()

        XCTAssertEqual(viewModel.devices, provider.devices)
        XCTAssertEqual(viewModel.selectedDeviceID, "built-in")
        XCTAssertTrue(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.start, 1)
    }

    func testDisappearStopsStandaloneMonitor() async {
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor
        )
        await viewModel.appear()

        await viewModel.disappear()

        XCTAssertFalse(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.stop, 1)
    }

    func testRecordingSessionDoesNotStartMonitorOrSwitchSharedDevice() async {
        let source = StubSetupSessionSource(state: .capturing)
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor,
            initialSessionSnapshot: SessionSnapshot(sessionState: .capturing),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )

        await viewModel.appear()
        await viewModel.selectDevice(id: "usb")

        XCTAssertEqual(provider.selectedDeviceID, "built-in")
        XCTAssertFalse(viewModel.isMonitoring)
        let counts = await monitor.counts()
        XCTAssertEqual(counts.start, 0)
    }

    func testPausedSessionDoesNotStartMonitorOrSwitchSharedDevice() async {
        let source = StubSetupSessionSource(state: .paused)
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor,
            initialSessionSnapshot: SessionSnapshot(sessionState: .paused),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )

        await viewModel.appear()
        await viewModel.selectDevice(id: "usb")

        XCTAssertEqual(provider.selectedDeviceID, "built-in")
        let counts = await monitor.counts()
        XCTAssertEqual(counts.start, 0)
    }

    func testSelectingDevicePersistsAndRestartsMonitor() async {
        let provider = StubSetupInputDeviceProvider()
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: provider,
            levelMonitor: monitor
        )
        await viewModel.appear()

        await viewModel.selectDevice(id: "usb")

        XCTAssertEqual(provider.selectedDeviceID, "usb")
        XCTAssertEqual(viewModel.selectedDeviceID, "usb")
        let counts = await monitor.counts()
        XCTAssertEqual(counts.stop, 1)
        XCTAssertEqual(counts.start, 2)
    }

    func testMonitorStopsForRecordingThenResetsAndRestartsWhenIdle() async {
        let source = StubSetupSessionSource(state: .idle)
        let monitor = StubAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor,
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )
        await viewModel.appear()
        await waitUntil { await monitor.counts().start == 1 }

        await source.send(SessionSnapshot(sessionState: .capturing))
        await waitUntil { await monitor.counts().stop >= 1 }
        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertEqual(viewModel.level, 0)

        await source.send(SessionSnapshot(sessionState: .idle))
        await waitUntil { await monitor.counts().start == 2 }
        XCTAssertTrue(viewModel.isMonitoring)
    }

    func testLeavingStepWhileStartIsSuspendedStopsLateEngineStart() async {
        let monitor = SuspendedStartAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor
        )

        let appear = Task { await viewModel.appear() }
        await waitUntil { await monitor.startCount == 1 }
        await viewModel.disappear()
        await monitor.resumeStart()
        await appear.value

        XCTAssertFalse(viewModel.isMonitoring)
        XCTAssertEqual(viewModel.level, 0)
        let stopCount = await monitor.stopCount
        XCTAssertGreaterThanOrEqual(stopCount, 1)
    }

    func testStaleStartDoesNotStopNewerMonitor() async {
        let monitor = RestartRaceAudioLevelMonitor()
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: monitor
        )

        let firstAppear = Task { await viewModel.appear() }
        await waitUntil { await monitor.startCount == 1 }
        await viewModel.disappear()

        await viewModel.appear()
        await waitUntil { await monitor.startCount == 2 }
        XCTAssertTrue(viewModel.isMonitoring)
        let stopCountBeforeStaleStartReturns = await monitor.stopCount

        await monitor.resumeFirstStart()
        await firstAppear.value

        XCTAssertTrue(viewModel.isMonitoring)
        let finalStopCount = await monitor.stopCount
        XCTAssertEqual(finalStopCount, stopCountBeforeStaleStartReturns)
    }

    func testSessionSnapshotsPublishOnlyWhenSetupUsesThem() async {
        let source = StubSetupSessionSource(state: .idle)
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: StubAudioLevelMonitor(),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )
        var publicationCount = 0
        let cancellable = viewModel.objectWillChange.sink { publicationCount += 1 }

        await source.send(
            SessionSnapshot(sessionState: .capturing, recordingDuration: .seconds(1))
        )
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(publicationCount, 0)
        XCTAssertEqual(viewModel.sessionState.displayState, .idle)

        await viewModel.setPracticeVisible(true)
        XCTAssertEqual(viewModel.sessionState.displayState, .capturing)
        XCTAssertEqual(viewModel.recordingElapsedSeconds, 1)
        _ = cancellable
    }

    func testSessionSnapshotsAreSubscribedOnlyWhileSetupUsesMicrophoneState() async {
        let source = StubSetupSessionSource(state: .idle)
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: StubAudioLevelMonitor(),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )

        await Task.yield()
        let initialStreamCalls = await source.streamCallCount
        let initialSubscriptions = await source.activeSubscriptionCount
        XCTAssertEqual(initialStreamCalls, 0)
        XCTAssertEqual(initialSubscriptions, 0)

        await viewModel.appear()
        await waitUntil { await source.activeSubscriptionCount == 1 }
        let microphoneStreamCalls = await source.streamCallCount
        XCTAssertEqual(microphoneStreamCalls, 1)

        await viewModel.disappear()
        await waitUntil { await source.activeSubscriptionCount == 0 }

        await viewModel.setPracticeVisible(true)
        await waitUntil { await source.activeSubscriptionCount == 1 }
        let practiceStreamCalls = await source.streamCallCount
        XCTAssertEqual(practiceStreamCalls, 2)

        await viewModel.windowDidHide()
        await waitUntil { await source.activeSubscriptionCount == 0 }

        await viewModel.setPracticeVisible(true)
        await waitUntil { await source.activeSubscriptionCount == 1 }
        await viewModel.setPracticeVisible(false)
        await waitUntil { await source.activeSubscriptionCount == 0 }
    }

    func testPracticeStopArmsBeforeCompletionAndEmptyCompletionDiscards() async {
        let source = StubSetupSessionSource(state: .idle)
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: StubAudioLevelMonitor(),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )
        await viewModel.setPracticeVisible(true)

        await source.send(SessionSnapshot(sessionState: .capturing))
        await waitUntil {
            if case .captureStarted = viewModel.practiceSessionEvent { return true }
            return false
        }
        await source.send(
            SessionSnapshot(
                sessionState: .completed,
                lastCompletedResult: Self.result(text: "   ")
            )
        )
        try? await Task.sleep(for: .milliseconds(20))
        guard case .discarded = viewModel.practiceSessionEvent else {
            return XCTFail("An empty transcript must discard the stopped capture")
        }

        await source.send(SessionSnapshot(sessionState: .capturing))
        await waitUntil {
            if case .captureStarted(4) = viewModel.practiceSessionEvent { return true }
            return false
        }
        await source.send(SessionSnapshot(sessionState: .transcribing))
        await waitUntil {
            if case .captureStopped = viewModel.practiceSessionEvent { return true }
            return false
        }
        await source.send(
            SessionSnapshot(
                sessionState: .completed,
                lastCompletedResult: Self.result(text: "Hello Ninimma")
            )
        )
        try? await Task.sleep(for: .milliseconds(20))
        guard case .captureStopped = viewModel.practiceSessionEvent else {
            return XCTFail("A non-empty completion must preserve the stop arm")
        }
    }

    func testVisibilityResyncDoesNotEmitPracticeCompletion() async {
        let source = StubSetupSessionSource(state: .capturing)
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: StubAudioLevelMonitor(),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() }
        )

        await viewModel.setPracticeVisible(true)
        await waitUntil { await source.activeSubscriptionCount == 1 }
        try? await Task.sleep(for: .milliseconds(20))
        XCTAssertNil(viewModel.practiceSessionEvent)
        await viewModel.windowDidHide()
        await source.send(
            SessionSnapshot(
                sessionState: .completed,
                lastCompletedResult: Self.result(text: "Finished while hidden")
            )
        )

        await viewModel.setPracticeVisible(true)
        await waitUntil { await source.activeSubscriptionCount == 1 }
        try? await Task.sleep(for: .milliseconds(20))

        XCTAssertNil(viewModel.practiceSessionEvent)
        XCTAssertEqual(viewModel.sessionState, .completed)
    }

    func testPracticeWaveformUsesRecordingAudioLevel() async {
        let source = StubSetupSessionSource(state: .capturing)
        let viewModel = SetupMicrophoneViewModel(
            inputDeviceProvider: StubSetupInputDeviceProvider(),
            levelMonitor: StubAudioLevelMonitor(),
            currentSessionSnapshot: { await source.current() },
            sessionSnapshots: { await source.stream() },
            recordingAudioLevels: {
                AsyncStream { continuation in
                    continuation.yield(0.82)
                    continuation.finish()
                }
            }
        )

        await viewModel.setPracticeVisible(true)
        await waitUntil { viewModel.level == 0.82 }

        XCTAssertEqual(viewModel.level, 0.82)
        await viewModel.setPracticeVisible(false)
        XCTAssertEqual(viewModel.level, 0)
    }

    private func waitUntil(
        timeout: Duration = .seconds(1),
        condition: @escaping @MainActor @Sendable () async -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline {
            if await condition() { return }
            await Task.yield()
        }
        XCTFail("Timed out waiting for condition")
    }

    private static func result(text: String) -> TranscriptionResult {
        TranscriptionResult(
            text: text,
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(100)
        )
    }
}

private final class StubSetupInputDeviceProvider: AudioInputDeviceProviding, @unchecked Sendable {
    let devices = [
        AudioInputDevice(id: "built-in", name: "MacBook Pro Microphone"),
        AudioInputDevice(id: "usb", name: "USB Microphone"),
    ]
    var selectedDeviceID: String? = "built-in"
    var systemDefaultDeviceID: String? = "built-in"

    func availableDevices() -> [AudioInputDevice] { devices }
    func selectDevice(id: String?) { selectedDeviceID = id }
}

private actor StubAudioLevelMonitor: AudioLevelMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() async throws -> AsyncStream<Float> {
        startCount += 1
        return AsyncStream { continuation in
            continuation.yield(0.6)
        }
    }

    func stop() async {
        stopCount += 1
    }

    func counts() -> (start: Int, stop: Int) {
        (startCount, stopCount)
    }
}

private actor StubSetupSessionSource {
    private var snapshot: SessionSnapshot
    private var continuations: [UUID: AsyncStream<SessionSnapshot>.Continuation] = [:]
    private(set) var streamCallCount = 0

    var activeSubscriptionCount: Int { continuations.count }

    init(state: SessionState) {
        snapshot = SessionSnapshot(sessionState: state)
    }

    func current() -> SessionSnapshot { snapshot }

    func stream() -> AsyncStream<SessionSnapshot> {
        streamCallCount += 1
        let id = UUID()
        return AsyncStream { continuation in
            continuations[id] = continuation
            continuation.yield(snapshot)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.remove(id) }
            }
        }
    }

    func send(_ snapshot: SessionSnapshot) {
        self.snapshot = snapshot
        continuations.values.forEach { $0.yield(snapshot) }
    }

    private func remove(_ id: UUID) {
        continuations[id] = nil
    }
}

private actor SuspendedStartAudioLevelMonitor: AudioLevelMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var startContinuation: CheckedContinuation<Void, Never>?

    func start() async throws -> AsyncStream<Float> {
        startCount += 1
        await withCheckedContinuation { continuation in
            startContinuation = continuation
        }
        return AsyncStream { _ in }
    }

    func stop() async {
        stopCount += 1
    }

    func resumeStart() {
        startContinuation?.resume()
        startContinuation = nil
    }
}

private actor RestartRaceAudioLevelMonitor: AudioLevelMonitoring {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private var firstStartContinuation: CheckedContinuation<Void, Never>?

    func start() async throws -> AsyncStream<Float> {
        startCount += 1
        if startCount == 1 {
            await withCheckedContinuation { continuation in
                firstStartContinuation = continuation
            }
        }
        return AsyncStream { _ in }
    }

    func stop() async {
        stopCount += 1
    }

    func resumeFirstStart() {
        firstStartContinuation?.resume()
        firstStartContinuation = nil
    }
}
