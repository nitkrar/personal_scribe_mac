import CoreGraphics
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `HotkeyEventTap` — the CGEventTap wrapper landed in
/// 5a-v1 commit 2 for system-wide hotkey swallowing (bug #5a).
///
/// The tap + run-loop plumbing is exercised via the `Installer` DI
/// seam: tests inject a fake that returns `nil` (simulate permission
/// denied) or a sentinel `CFMachPort` (simulate a working install)
/// without touching the real HID event system.
@MainActor
final class HotkeyEventTapTests: XCTestCase {
    func testStartReturnsFalseWhenInstallerReturnsNil() {
        var installerCalls = 0
        let tap = HotkeyEventTap(
            decider: { _ in false },
            installer: { _, _ in
                installerCalls += 1
                return nil
            }
        )

        XCTAssertFalse(tap.start())
        XCTAssertEqual(installerCalls, 1)
        XCTAssertFalse(tap.isActive)
    }

    func testStartIsIdempotentWhenAlreadyActive() throws {
        // Build a real CFMachPort we can legitimately use as the
        // installer's return value without ever hitting the OS's HID
        // event system. `CFMachPortCreate` with a no-op callback
        // gives us a port that's safe to add to a run loop and then
        // tear down cleanly via `stop()`.
        let installer: HotkeyEventTap.Installer = { _, _ in
            Self.makeFakePort()
        }
        let tap = HotkeyEventTap(
            decider: { _ in false },
            installer: installer
        )

        XCTAssertTrue(tap.start())
        XCTAssertTrue(tap.isActive)

        // Second start should be a no-op (still reports true; state
        // doesn't churn).
        XCTAssertTrue(tap.start())
        XCTAssertTrue(tap.isActive)

        tap.stop()
        XCTAssertFalse(tap.isActive)
    }

    func testStopAfterFailedStartIsNoOp() {
        let tap = HotkeyEventTap(
            decider: { _ in false },
            installer: { _, _ in nil }
        )
        XCTAssertFalse(tap.start())
        tap.stop()  // must not crash on nil tap
        XCTAssertFalse(tap.isActive)
    }

    // MARK: - Helpers

    /// Builds a harmless `CFMachPort` — callback is a no-op. We use
    /// this to simulate a successful `CGEvent.tapCreate` without
    /// registering a real HID event tap.
    private static func makeFakePort() -> CFMachPort? {
        var context = CFMachPortContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        return CFMachPortCreate(
            nil,
            { _, _, _, _ in },
            &context,
            nil
        )
    }
}
