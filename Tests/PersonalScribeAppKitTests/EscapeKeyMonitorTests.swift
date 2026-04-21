import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `EscapeKeyMonitor`'s filter logic (pill UX spec §3 — Esc
/// cancels an active recording).
@MainActor
final class EscapeKeyMonitorTests: XCTestCase {
    func testStartInstallsSystemMonitor() {
        var installCalls = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: {},
            install: { _, _ in
                installCalls += 1
                return "mock-handle"
            },
            uninstall: { _ in }
        )

        monitor.start()

        XCTAssertEqual(installCalls, 1)
        XCTAssertTrue(monitor.isActive)
    }

    func testStartIsIdempotent() {
        var installCalls = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: {},
            install: { _, _ in
                installCalls += 1
                return "mock-handle"
            },
            uninstall: { _ in }
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(installCalls, 1, "Duplicate start must not re-install")
    }

    func testStopRemovesSystemMonitor() {
        var uninstallCalls = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: {},
            install: { _, _ in "mock-handle" },
            uninstall: { _ in
                uninstallCalls += 1
            }
        )
        monitor.start()

        monitor.stop()

        XCTAssertEqual(uninstallCalls, 1)
        XCTAssertFalse(monitor.isActive)
    }

    func testPlainEscapeKeyDownFiresCallback() throws {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { fireCount += 1 },
            install: { _, _ in nil },
            uninstall: { _ in }
        )

        monitor.handle(event: try makeKeyDownEvent(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertEqual(fireCount, 1)
    }

    /// Spec intent: plain Esc cancels. Modified Esc (Cmd+Esc, Option+Esc,
    /// etc.) is left alone — those are system / app shortcuts we don't
    /// want to intercept.
    func testEscapeWithModifierIsIgnored() throws {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { fireCount += 1 },
            install: { _, _ in nil },
            uninstall: { _ in }
        )

        for flags: NSEvent.ModifierFlags in [[.command], [.option], [.control], [.shift], [.command, .shift]] {
            monitor.handle(event: try makeKeyDownEvent(
                keyCode: EscapeKeyMonitor.escapeKeyCode,
                modifierFlags: flags
            ))
        }

        XCTAssertEqual(fireCount, 0)
    }

    func testNonEscapeKeyCodeIsIgnored() throws {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { fireCount += 1 },
            install: { _, _ in nil },
            uninstall: { _ in }
        )

        // keyCode 36 = Return
        monitor.handle(event: try makeKeyDownEvent(
            keyCode: 36,
            modifierFlags: []
        ))

        XCTAssertEqual(fireCount, 0)
    }

    private func makeKeyDownEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 1.0,
                windowNumber: 0,
                context: nil,
                characters: "",
                charactersIgnoringModifiers: "",
                isARepeat: false,
                keyCode: keyCode
            )
        )
    }
}
