import AppKit
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class GlobalHotkeyMonitorTests: XCTestCase {
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
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [], timestamp: 1.05))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.2))

        XCTAssertEqual(triggerCount, 1)
    }

    func testDoubleTapOutsideWindowDoesNotTrigger() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [], timestamp: 1.2))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.6))

        XCTAssertEqual(triggerCount, 0)
    }

    func testTripleTapFiresOnceAndRearms() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.0))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [], timestamp: 1.05))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.1))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [], timestamp: 1.15))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.2))

        XCTAssertEqual(triggerCount, 1)
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

    private func makeFlagsChangedEvent(
        modifierFlags: NSEvent.ModifierFlags,
        timestamp: TimeInterval
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
                keyCode: 61
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
