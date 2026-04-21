import Combine
import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

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

    /// Double-tap MUST fire immediately on the second matching tap. The
    /// previous implementation deferred by `tapWindow` (~400ms) to
    /// disambiguate a third tap for emergency-quit; that path was
    /// removed and the monitor must now respond with no synthetic delay.
    func testDoubleTapWithinWindowFiresImmediately() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                triggerCount += 1
            }
        )

        try sendTap(to: monitor, at: 1.0)
        XCTAssertEqual(triggerCount, 0, "first tap must not fire")

        try sendTap(to: monitor, at: 1.2)
        XCTAssertEqual(triggerCount, 1, "second tap within window must fire with no deferral")
    }

    func testDoubleTapOutsideWindowDoesNotTrigger() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                triggerCount += 1
            }
        )

        try sendTap(to: monitor, at: 1.0)
        try sendTap(to: monitor, at: 1.6)

        XCTAssertEqual(triggerCount, 0)
    }

    func testTwoRightOptionTapsInsideWindowFiresToggleImmediately() throws {
        var toggleCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            }
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.rightOptionKeyCode)
        XCTAssertEqual(toggleCount, 0)

        try sendTap(to: monitor, at: 1.2, keyCode: Self.rightOptionKeyCode)
        XCTAssertEqual(toggleCount, 1)
    }

    /// After a completed double-tap toggle, a later tap outside the
    /// window starts a fresh sequence (no emergency-quit on the third
    /// tap — that behaviour was removed).
    func testThirdRightOptionTapOutsideWindowStartsFreshSequence() throws {
        var toggleCount = 0
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {
                toggleCount += 1
            }
        )

        try sendTap(to: monitor, at: 1.0, keyCode: Self.rightOptionKeyCode)
        try sendTap(to: monitor, at: 1.2, keyCode: Self.rightOptionKeyCode)
        XCTAssertEqual(toggleCount, 1)

        // 1.7 is > 0.4s after the 1.2 tap — outside the window, so the
        // sequence resets and this tap alone does nothing.
        try sendTap(to: monitor, at: 1.7, keyCode: Self.rightOptionKeyCode)

        XCTAssertEqual(toggleCount, 1)
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

        var doubleTapTriggerCount = 0
        let doubleTapMonitor = GlobalHotkeyMonitor(
            onTrigger: {
                doubleTapTriggerCount += 1
            },
            recordingHotkey: HotkeyPreference(
                keyCode: Self.leftOptionKeyCode,
                tapCount: 2,
                modifiers: 0
            )
        )

        try sendTap(to: doubleTapMonitor, at: 2.0, keyCode: Self.leftOptionKeyCode)
        try sendTap(to: doubleTapMonitor, at: 2.2, keyCode: Self.leftOptionKeyCode)

        XCTAssertEqual(doubleTapTriggerCount, 1)
    }

    // MARK: - Phase 1 Step 1.9 — Input Monitoring permission warning

    func testNilMonitorFailureEmitsDeniedWarningThroughLogSink() {
        let permissionService = FakePermissionService(
            statuses: [.inputMonitoring: .denied]
        )
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {},
            permissionService: permissionService,
            logSink: sink.capture
        )

        monitor.handleMonitorInstallFailure()

        let captured = sink.snapshot()
        XCTAssertEqual(captured.count, 1)
        XCTAssertEqual(captured.first?.level, "error")
        XCTAssertTrue(captured.first?.message.contains("Input Monitoring permission denied") == true)
        XCTAssertTrue(captured.first?.message.contains("menu bar warning") == true)
    }

    func testNilMonitorFailureReportsPendingWhenTCCUnresolved() {
        let permissionService = FakePermissionService(
            statuses: [.inputMonitoring: .pending]
        )
        let sink = CapturingLogSink()
        let monitor = GlobalHotkeyMonitor(
            onTrigger: {},
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
