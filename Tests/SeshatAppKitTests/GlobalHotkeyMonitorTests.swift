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
}
