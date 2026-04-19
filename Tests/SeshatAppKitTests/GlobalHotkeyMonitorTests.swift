import AppKit
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class GlobalHotkeyMonitorTests: XCTestCase {
    private static let leftOptionKeyCode: UInt16 = 58
    private static let rightOptionKeyCode: UInt16 = 61

    func testStartStopLifecycle() {
        let monitor = GlobalHotkeyMonitor(onTrigger: {})

        monitor.start()

        XCTAssertTrue(monitor.isActive)

        monitor.stop()

        XCTAssertFalse(monitor.isActive)
    }

    func testStartIsIdempotent() {
        let monitor = GlobalHotkeyMonitor(onTrigger: {})

        monitor.start()
        monitor.start()

        XCTAssertTrue(monitor.isActive)
    }

    func testSinglePressDoesNotTrigger() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1))

        XCTAssertEqual(triggerCount, 0)
    }

    func testDoubleTapWithinWindowTriggersOnce() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                triggerCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0)
        try sendTap(to: monitor, at: 1.2)

        XCTAssertEqual(triggerCount, 0)

        scheduler.fireScheduledActions()

        XCTAssertEqual(triggerCount, 1)
    }

    func testDoubleTapOutsideWindowDoesNotTrigger() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                triggerCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0)
        try sendTap(to: monitor, at: 1.6)

        scheduler.fireScheduledActions()

        XCTAssertEqual(triggerCount, 0)
    }

    func testTripleTapCancelsPendingToggleAndRequestsEmergencyQuit() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0)
        try sendTap(to: monitor, at: 1.2)
        try sendTap(to: monitor, at: 1.35)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(emergencyQuitCount, 1)
    }

    func testThreeRightOptionTapsInsideWindowRequestsEmergencyQuitWithoutToggle() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.35, keyCode: Self.rightOptionKeyCode)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(emergencyQuitCount, 1)
    }

    func testTwoRightOptionTapsInsideWindowRequestsToggleWithoutEmergencyQuit() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.rightOptionKeyCode)

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(emergencyQuitCount, 0)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(emergencyQuitCount, 0)
    }

    func testThirdRightOptionTapOutsideWindowKeepsDoubleTapToggleAndStartsNewSequence() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.7, keyCode: Self.rightOptionKeyCode)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 1)
        XCTAssertEqual(emergencyQuitCount, 0)
    }

    func testMonitorReadsPreferenceForKeyCodeAndTapCount() throws {
        var singleTapTriggerCount = 0
        let singleTapMonitor = GlobalHotkeyMonitor(
            onTrigger: {
                singleTapTriggerCount += 1
            },
            recordingHotkey: HotkeyPreference(
                keyCode: 15,
                tapCount: 1,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            )
        )

        singleTapMonitor.handle(event: try makeKeyDownEvent(
            keyCode: 15,
            modifierFlags: [.command],
            characters: "r",
            timestamp: 1.0
        ))
        singleTapMonitor.handle(event: try makeKeyDownEvent(
            keyCode: 15,
            modifierFlags: [],
            characters: "r",
            timestamp: 1.2
        ))

        XCTAssertEqual(singleTapTriggerCount, 1)

        let scheduler = DeferredActionSchedulerSpy()
        var doubleTapTriggerCount = 0
        let doubleTapMonitor = GlobalHotkeyMonitor(
            onTrigger: {
                doubleTapTriggerCount += 1
            },
            recordingHotkey: HotkeyPreference(
                keyCode: Self.leftOptionKeyCode,
                tapCount: 2,
                modifiers: 0
            ),
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: doubleTapMonitor, at: 2.0, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: doubleTapMonitor, at: 2.2, keyCode: Self.leftOptionKeyCode)

        XCTAssertEqual(doubleTapTriggerCount, 0)

        scheduler.fireScheduledActions()

        XCTAssertEqual(doubleTapTriggerCount, 1)
    }

    func testThreeLeftOptionTapsInsideWindowRequestsEmergencyQuitWithoutToggle() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: monitor, at: 1.35, keyCode: Self.leftOptionKeyCode)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(emergencyQuitCount, 1)
    }

    func testTripleTapEmergencyQuitStillFiresRegardlessOfRecordingHotkeyPreference() throws {
        let scheduler = DeferredActionSchedulerSpy()
        var toggleCount = 0
        var emergencyQuitCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            },
            emergencyQuitRequested: {
                emergencyQuitCount += 1
            },
            recordingHotkey: HotkeyPreference(
                keyCode: 15,
                tapCount: 1,
                modifiers: NSEvent.ModifierFlags.command.rawValue
            ),
            scheduleDeferredTrigger: scheduler.schedule
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: monitor, at: 1.35, keyCode: Self.leftOptionKeyCode)

        scheduler.fireScheduledActions()

        XCTAssertEqual(toggleCount, 0)
        XCTAssertEqual(emergencyQuitCount, 1)
    }

    // MARK: - Phase 1 Step 1.9 — Input Monitoring permission warning

    func testNilMonitorFailureEmitsDeniedWarningThroughLogSink() {
        let probe = StubProbe(stubbed: .denied)
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {},
            permissionProbe: probe,
            logSink: sink.capture
        )

        monitor.handleMonitorInstallFailure()

        let captured = sink.snapshot()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.level, "error")
        XCTAssertTrue(captured.first?.message.contains("Input Monitoring permission denied") == true)
        XCTAssertTrue(captured.first?.message.contains("Phase 2 NSMenu") == true)
    }

    func testNilMonitorFailureReportsNotDeterminedWhenTCCUnresolved() {
        let probe = StubProbe(stubbed: .notDetermined)
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {},
            permissionProbe: probe,
            logSink: sink.capture
        )

        monitor.handleMonitorInstallFailure()

        XCTAssertTrue(sink.snapshot().first?.message.contains("not yet determined") == true)
    }

    func testFailureMessageMentionsGrantedPathWhenProbeReportsGrantedDespiteNilMonitor() {
        let message = GlobalHotkeyMonitor.monitorInstallFailureMessage(for: .granted)

        XCTAssertTrue(message.contains("reporting granted"))
    }

    private func sendTap(
        to monitor: GlobalHotkeyMonitor,
        at timestamp: TimeInterval,
        releaseDelay: TimeInterval = 0.05,
        keyCode: UInt16 = 61
    ) throws {
        monitor.handle(event: try makeFlagsChangedEvent(
            modifierFlags: [.option],
            timestamp: timestamp,
            keyCode: keyCode
        ))
        monitor.handle(event: try makeFlagsChangedEvent(
            modifierFlags: [],
            timestamp: timestamp + releaseDelay,
            keyCode: keyCode
        ))
    }

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval,
        keyCode: UInt16 = 61
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .flagsChanged,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: timestamp,
                windowNumber: 0,
                context: nil,
                characters: characters,
                charactersIgnoringModifiers: characters.lowercased(),
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}

private struct StubProbe: PermissionProbing {
    let stubbed: InputMonitoringPermissionState
    func checkInputMonitoring() -> InputMonitoringPermissionState { stubbed }
}

private final class CapturingLogSink: @unchecked Sendable {
    struct Entry: Sendable {
        let level: String
        let message: String
    }

    private let lock = NSLock()
    private var entries: [Entry] = []

    var capture: @Sendable (String, String) -> Void {
        { [weak self] level, message in
            self?.lock.withLock {
                self?.entries.append(Entry(level: level, message: message))
            }
        }
    }

    func snapshot() -> [Entry] {
        lock.withLock { entries }
    }
}

@MainActor
private final class DeferredActionSchedulerSpy {
    private final class ScheduledAction {
        let delay: TimeInterval
        let action: @MainActor () -> Void
        var isCancelled = false

        init(delay: TimeInterval, action: @escaping @MainActor () -> Void) {
            self.delay = delay
            self.action = action
        }
    }

    private var scheduledActions: [ScheduledAction] = []

    var schedule: GlobalHotkeyMonitor.DeferredActionScheduler {
        { [weak self] delay, action in
            let scheduledAction = ScheduledAction(delay: delay, action: action)
            self?.scheduledActions.append(scheduledAction)
            return {
                scheduledAction.isCancelled = true
            }
        }
    }

    func fireScheduledActions() {
        let pending = scheduledActions
        scheduledActions.removeAll()

        for scheduledAction in pending where scheduledAction.isCancelled == false {
            scheduledAction.action()
        }
    }
}
