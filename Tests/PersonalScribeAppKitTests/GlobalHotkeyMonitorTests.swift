import Combine
import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Tests for `GlobalHotkeyMonitor`'s Phase 4 tap / hold / double-tap
/// state machine (pill UX spec §3).
///
/// The monitor listens for `.keyDown` + `.keyUp` on a key+modifier
/// combination and dispatches to three callbacks:
///
/// * `onToggle` — tap release (press+release < 300 ms). Debounced
///   against subsequent taps within 400 ms (double-tap is an alias).
/// * `onHoldStart` — held past 300 ms without release. Fired exactly
///   once per press.
/// * `onHoldRelease` — released after `onHoldStart` fired.
///
/// `scheduleHoldDetection` is dependency-injected so tests drive the
/// hold-threshold timer deterministically instead of waiting on real
/// time.
@MainActor
final class GlobalHotkeyMonitorTests: XCTestCase {
    private static let slashKeyCode: UInt16 = 44
    private static let optSlash: HotkeyPreference = HotkeyPreference(
        keyCode: 44,
        tapCount: 1,
        modifiers: NSEvent.ModifierFlags.option.rawValue
    )

    func testStartStopLifecycle() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})

        monitor.start()
        XCTAssertTrue(monitor.isActive)

        monitor.stop()
        XCTAssertFalse(monitor.isActive)
    }

    func testStartIsIdempotent() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})

        monitor.start()
        monitor.start()

        XCTAssertTrue(monitor.isActive)
    }

    // MARK: - HotkeyEvent adapter (5a-v1 c1)

    func testHotkeyEventAdapterPreservesRepeatFlag() throws {
        let repeatEvent = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: 1.2,
            isARepeat: true
        )
        let hotkeyEvent = HotkeyEvent(nsEvent: repeatEvent)
        XCTAssertTrue(hotkeyEvent.isARepeat)
        XCTAssertEqual(hotkeyEvent.type, .keyDown)
        XCTAssertEqual(hotkeyEvent.keyCode, Self.slashKeyCode)
        XCTAssertTrue(hotkeyEvent.modifierFlags.contains(.option))
    }

    func testHotkeyEventAdapterMapsKeyUpWithoutModifiers() throws {
        // User often releases option before /, so keyUp may have no modifiers.
        let keyUpEvent = try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.4
        )
        let hotkeyEvent = HotkeyEvent(nsEvent: keyUpEvent)
        XCTAssertEqual(hotkeyEvent.type, .keyUp)
        XCTAssertEqual(hotkeyEvent.keyCode, Self.slashKeyCode)
        XCTAssertTrue(hotkeyEvent.modifierFlags.isEmpty)
        XCTAssertFalse(hotkeyEvent.isARepeat, "isARepeat must be false for keyUp")
    }

    // MARK: - Tap (single short press+release)

    func testQuickTapFiresToggleOnRelease() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        var holds = 0
        var releases = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            onHoldStart: { holds += 1 },
            onHoldRelease: { releases += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        XCTAssertEqual(toggles, 0, "Tap must not fire until release")

        try sendKeyUp(to: monitor, at: 1.15) // 150 ms — under hold threshold

        XCTAssertEqual(toggles, 1)
        XCTAssertEqual(holds, 0)
        XCTAssertEqual(releases, 0)
    }

    func testTapOutsideDebounceWindowFiresAgain() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        try sendKeyUp(to: monitor, at: 1.1)
        XCTAssertEqual(toggles, 1)

        // Second tap 500 ms after the first → outside 400 ms debounce.
        try sendKeyDown(to: monitor, at: 1.6)
        try sendKeyUp(to: monitor, at: 1.7)
        XCTAssertEqual(toggles, 2)
    }

    // MARK: - Double-tap alias (spec §3 — fires ONCE, second absorbed)

    func testDoubleTapFiresToggleOnceAndAbsorbsSecondTap() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        try sendKeyUp(to: monitor, at: 1.1)  // 1st tap

        try sendKeyDown(to: monitor, at: 1.25)
        try sendKeyUp(to: monitor, at: 1.3)  // 2nd tap, 200 ms after 1st → absorbed

        XCTAssertEqual(
            toggles,
            1,
            "Spec §3: double-tap is an alias for single tap, not two toggles"
        )
    }

    // MARK: - Hold

    func testHoldPastThresholdFiresHoldStartOnlyOnce() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        var holdStarts = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            onHoldStart: { holdStarts += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        // Simulate the 300 ms hold timer elapsing while the key is
        // still down.
        scheduler.fireScheduledActions()

        XCTAssertEqual(holdStarts, 1)
        XCTAssertEqual(toggles, 0)
    }

    func testHoldReleaseFiresOnlyHoldReleaseNotToggle() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        var holdStarts = 0
        var holdReleases = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            onHoldStart: { holdStarts += 1 },
            onHoldRelease: { holdReleases += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        scheduler.fireScheduledActions()  // 300 ms elapses → hold start
        try sendKeyUp(to: monitor, at: 1.8)  // released 800 ms after down

        XCTAssertEqual(holdStarts, 1)
        XCTAssertEqual(holdReleases, 1)
        XCTAssertEqual(toggles, 0, "Hold release must not also fire a toggle")
    }

    /// If the hold detector was cancelled or didn't fire in time but
    /// the keyUp lands past the hold threshold, treat as a hold
    /// release anyway — the tap path would be misleading after such
    /// a long press.
    func testKeyUpPastThresholdTreatedAsHoldReleaseEvenIfTimerDidntFire() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        var holdReleases = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            onHoldRelease: { holdReleases += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        try sendKeyUp(to: monitor, at: 1.5)  // 500 ms — past 300 ms threshold

        XCTAssertEqual(holdReleases, 1)
        XCTAssertEqual(toggles, 0)
    }

    // MARK: - Hotkey filter

    func testNonMatchingKeyCodeIsIgnored() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        // `a` keyCode with .option modifier — not our hotkey.
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: 0,
            modifierFlags: [.option],
            characters: "a",
            timestamp: 1.0
        ))
        monitor.handle(event: try makeKeyUpEvent(
            keyCode: 0,
            modifierFlags: [.option],
            characters: "a",
            timestamp: 1.05
        ))

        XCTAssertEqual(toggles, 0)
    }

    func testMissingModifierIsIgnored() throws {
        let scheduler = HoldSchedulerSpy()
        var toggles = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        // `/` without .option — not our hotkey.
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.0
        ))
        monitor.handle(event: try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.05
        ))

        XCTAssertEqual(toggles, 0)
    }

    func testKeyRepeatIsIgnoredAndDoesNotRestartHoldTimer() throws {
        let scheduler = HoldSchedulerSpy()
        var holdStarts = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            onHoldStart: { holdStarts += 1 },
            recordingHotkey: Self.optSlash,
            scheduleHoldDetection: scheduler.schedule
        )

        try sendKeyDown(to: monitor, at: 1.0)
        // Fire the hold timer → we're now in hold state.
        scheduler.fireScheduledActions()
        XCTAssertEqual(holdStarts, 1)

        // A system-generated key-repeat keyDown should not re-trigger
        // the hold start callback.
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: 1.4,
            isARepeat: true
        ))
        XCTAssertEqual(holdStarts, 1)
    }

    // MARK: - Permission-failure logging (unchanged from Issue 4)

    func testNilMonitorFailureEmitsDeniedWarningThroughLogSink() {
        let permissionService = FakePermissionService(
            statuses: [.inputMonitoring: .denied]
        )
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            permissionService: permissionService,
            logSink: sink.capture
        )

        monitor.handleMonitorInstallFailure()

        let captured = sink.snapshot()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.level, "error")
        XCTAssertTrue(captured.first?.message.contains("Input Monitoring permission denied") == true)
    }

    func testNilMonitorFailureReportsPendingWhenTCCUnresolved() {
        let permissionService = FakePermissionService(
            statuses: [.inputMonitoring: .pending]
        )
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            permissionService: permissionService,
            logSink: sink.capture
        )

        monitor.handleMonitorInstallFailure()

        XCTAssertTrue(sink.snapshot().first?.message.contains("still pending") == true)
    }

    func testFailureMessageMentionsGrantedPathWhenProbeReportsGrantedDespiteNilMonitor() {
        let message = GlobalHotkeyMonitor.monitorInstallFailureMessage(for: PermissionStatus.granted)
        XCTAssertTrue(message.contains("reporting granted"))
    }

    // MARK: - Bug #4 — local monitor for in-app key events

    /// `NSEvent.addGlobalMonitorForEvents` only fires when the event is
    /// headed to *another* application; when Ninimma's own window is
    /// frontmost, key events never reach that monitor. `start()` must
    /// also install `addLocalMonitorForEvents` so the hotkey works when
    /// our window has focus (bug #4, 2026-04-21 dogfood).
    func testStartInstallsBothLocalAndGlobalMonitors() {
        let monitor = GlobalHotkeyMonitor(onToggle: {})

        monitor.start()
        XCTAssertTrue(
            monitor.isGlobalMonitorActive,
            "global monitor must be installed — fires when user is focused on another app"
        )
        XCTAssertTrue(
            monitor.isLocalMonitorActive,
            "local monitor must be installed — fires when Ninimma's window is frontmost (bug #4)"
        )

        monitor.stop()
        XCTAssertFalse(monitor.isGlobalMonitorActive)
        XCTAssertFalse(monitor.isLocalMonitorActive)
    }

    func testShouldSwallowLocalSwallowsMatchingHotkeyKeyDown() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        let event = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: 1.0
        )
        XCTAssertTrue(
            monitor.shouldSwallowLocal(event),
            "Matching hotkey keyDown must be swallowed so `÷` doesn't leak into our own text fields"
        )
    }

    func testShouldSwallowLocalSwallowsRepeatKeyDownSoAutoRepeatDoesNotType() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        let event = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: 1.2,
            isARepeat: true
        )
        XCTAssertTrue(
            monitor.shouldSwallowLocal(event),
            "Auto-repeat keyDowns during hold must also be swallowed — otherwise our text fields get `÷÷÷÷`"
        )
    }

    func testShouldSwallowLocalPassesThroughNonHotkeyKeyDown() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        // `/` without `.option` — normal slash typing.
        let event = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.0
        )
        XCTAssertFalse(
            monitor.shouldSwallowLocal(event),
            "Non-hotkey keyDowns must pass through so normal typing works"
        )
    }

    func testShouldSwallowLocalPassesThroughPlainSlashKeyUpAfterPlainSlashKeyDown() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        let keyDown = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.0
        )
        let keyUp = try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.1
        )

        XCTAssertFalse(monitor.shouldSwallowLocal(keyDown))
        XCTAssertFalse(
            monitor.shouldSwallowLocal(keyUp),
            "Plain slash typing must keep a balanced keyDown/keyUp pair"
        )
    }

    func testShouldSwallowLocalPassesThroughHotkeyKeyUpWithoutPriorSwallowedKeyDown() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        // User may release option before /, so keyUp arrives with no
        // modifiers. Without a swallowed matching keyDown, though, this
        // keyUp must pass through to keep local delivery balanced.
        let event = try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.1
        )
        XCTAssertFalse(
            monitor.shouldSwallowLocal(event),
            "A bare keyUp must not be swallowed unless its matching keyDown was swallowed first"
        )
    }

    func testShouldSwallowLocalSwallowsKeyUpOnlyAfterSwallowingMatchingKeyDown() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        let hotkeyKeyDown = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: 1.0
        )
        let hotkeyKeyUp = try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 1.1
        )
        let plainKeyDown = try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 2.0
        )
        let plainKeyUp = try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [],
            characters: "/",
            timestamp: 2.1
        )

        XCTAssertTrue(monitor.shouldSwallowLocal(hotkeyKeyDown))
        XCTAssertTrue(monitor.shouldSwallowLocal(hotkeyKeyUp))
        XCTAssertFalse(monitor.shouldSwallowLocal(plainKeyDown))
        XCTAssertFalse(
            monitor.shouldSwallowLocal(plainKeyUp),
            "The swallowed-hotkey state must clear after the matching keyUp"
        )
    }

    func testShouldSwallowLocalPassesThroughNonHotkeyKeyUp() throws {
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            recordingHotkey: Self.optSlash
        )
        // `a` keyCode — unrelated keyUp must pass through.
        let event = try makeKeyUpEvent(
            keyCode: 0,
            modifierFlags: [.option],
            characters: "a",
            timestamp: 1.0
        )
        XCTAssertFalse(monitor.shouldSwallowLocal(event))
    }

    func testStartDoesNotInstallLocalMonitorWhenGlobalInstallFails() {
        // Simulate CGEvent.tapCreate returning nil (Input Monitoring
        // permission denied). HotkeyEventTap.start() returns false;
        // GlobalHotkeyMonitor.start() must route that through
        // handleMonitorInstallFailure and leave both monitors inactive.
        var installerAttempts = 0
        let failingInstaller: HotkeyEventTap.Installer = { _, _ in
            installerAttempts += 1
            return nil
        }
        let monitor = GlobalHotkeyMonitor(
            onToggle: {},
            eventTapFactory: { decider in
                HotkeyEventTap(decider: decider, installer: failingInstaller)
            }
        )

        monitor.start()

        XCTAssertEqual(installerAttempts, 1)
        XCTAssertFalse(monitor.isGlobalMonitorActive)
        XCTAssertFalse(monitor.isLocalMonitorActive)

        // Subsequent start() must retry — the guard at the top of
        // start() is only triggered when a monitor is already active.
        monitor.start()

        XCTAssertEqual(installerAttempts, 2)
        XCTAssertFalse(monitor.isGlobalMonitorActive)
        XCTAssertFalse(monitor.isLocalMonitorActive)
    }

    // MARK: - Helpers

    private func sendKeyDown(
        to monitor: GlobalHotkeyMonitor,
        at timestamp: TimeInterval
    ) throws {
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: timestamp
        ))
    }

    private func sendKeyUp(
        to monitor: GlobalHotkeyMonitor,
        at timestamp: TimeInterval
    ) throws {
        monitor.handle(event: try makeKeyUpEvent(
            keyCode: Self.slashKeyCode,
            modifierFlags: [.option],
            characters: "/",
            timestamp: timestamp
        ))
    }

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        timestamp: TimeInterval,
        isARepeat: Bool = false
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
                isARepeat: isARepeat,
                keyCode: keyCode
            )
        )
    }

    private func makeKeyUpEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        timestamp: TimeInterval
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyUp,
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

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    init(statuses: [Permission: PermissionStatus] = [:]) {
        self.statuses = statuses
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
            prompted: false,
            openedSettings: false,
            requiresRelaunch: permission == .inputMonitoring,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
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
private final class HoldSchedulerSpy {
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

    var schedule: GlobalHotkeyMonitor.HoldScheduler {
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
        for action in pending where action.isCancelled == false {
            action.action()
        }
    }
}
