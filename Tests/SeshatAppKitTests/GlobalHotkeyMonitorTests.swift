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
