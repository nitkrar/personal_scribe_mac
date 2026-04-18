import AppKit
import XCTest
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

    func testCallbackInvokedOnSimulatedFlagsChangedEventWithRightOption() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1))

        XCTAssertEqual(triggerCount, 1)
    }

    func testDebounceSuppressesRapidRepeat() throws {
        var triggerCount = 0
        let monitor = GlobalHotkeyMonitor {
            triggerCount += 1
        }

        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [], timestamp: 1.005))
        monitor.handle(event: try makeFlagsChangedEvent(modifierFlags: [.option], timestamp: 1.01))

        XCTAssertEqual(triggerCount, 1)
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
