import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `EscapeKeyMonitor`'s filter logic (pill UX spec §3 — Esc
/// cancels an active recording).
@MainActor
final class EscapeKeyMonitorTests: XCTestCase {
    func testStartInstallsBothGlobalAndLocalMonitors() {
        var globalCalls = 0
        var localCalls = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { false },
            installGlobal: { _, _ in
                globalCalls += 1
                return "mock-global"
            },
            installLocal: { _, _ in
                localCalls += 1
                return "mock-local"
            },
            uninstall: { _ in }
        )

        monitor.start()

        XCTAssertEqual(globalCalls, 1)
        XCTAssertEqual(localCalls, 1)
        XCTAssertTrue(monitor.isActive)
    }

    func testStartIsIdempotent() {
        var globalCalls = 0
        var localCalls = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { false },
            installGlobal: { _, _ in
                globalCalls += 1
                return "mock-global"
            },
            installLocal: { _, _ in
                localCalls += 1
                return "mock-local"
            },
            uninstall: { _ in }
        )

        monitor.start()
        monitor.start()

        XCTAssertEqual(globalCalls, 1, "Duplicate start must not re-install global")
        XCTAssertEqual(localCalls, 1, "Duplicate start must not re-install local")
    }

    func testStopRemovesBothMonitors() {
        var uninstalledHandles: [String] = []
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { false },
            installGlobal: { _, _ in "mock-global" },
            installLocal: { _, _ in "mock-local" },
            uninstall: { handle in
                if let handle = handle as? String {
                    uninstalledHandles.append(handle)
                }
            }
        )
        monitor.start()

        monitor.stop()

        XCTAssertEqual(Set(uninstalledHandles), ["mock-global", "mock-local"])
        XCTAssertFalse(monitor.isActive)
    }

    func testPlainEscapeKeyDownFiresCallback() throws {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: {
                fireCount += 1
                return true
            },
            installGlobal: { _, _ in nil },
            installLocal: { _, _ in nil },
            uninstall: { _ in }
        )

        _ = monitor.handle(event: try makeKeyDownEvent(
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
            onEscapePressed: {
                fireCount += 1
                return true
            },
            installGlobal: { _, _ in nil },
            installLocal: { _, _ in nil },
            uninstall: { _ in }
        )

        for flags: NSEvent.ModifierFlags in [[.command], [.option], [.control], [.shift], [.command, .shift]] {
            _ = monitor.handle(event: try makeKeyDownEvent(
                keyCode: EscapeKeyMonitor.escapeKeyCode,
                modifierFlags: flags
            ))
        }

        XCTAssertEqual(fireCount, 0)
    }

    func testNonEscapeKeyCodeIsIgnored() throws {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(
            onEscapePressed: {
                fireCount += 1
                return true
            },
            installGlobal: { _, _ in nil },
            installLocal: { _, _ in nil },
            uninstall: { _ in }
        )

        // keyCode 36 = Return
        _ = monitor.handle(event: try makeKeyDownEvent(
            keyCode: 36,
            modifierFlags: []
        ))

        XCTAssertEqual(fireCount, 0)
    }

    /// Local-monitor leg: when Ninimma is frontmost (regular activation
    /// policy after the Background-mode refactor), keystrokes are
    /// delivered through the local monitor. Returning `nil` swallows
    /// the event so it doesn't bubble to text fields / SwiftUI
    /// handlers — pressing Esc during recording is unambiguously a
    /// cancel intent.
    func testLocalMonitorSwallowsEscapeWhenHandlerReportsHandled() throws {
        var capturedHandler: ((NSEvent) -> NSEvent?)?
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { true },
            installGlobal: { _, _ in nil },
            installLocal: { _, handler in
                capturedHandler = handler
                return "mock-local"
            },
            uninstall: { _ in }
        )

        monitor.start()
        let handler = try XCTUnwrap(capturedHandler)
        let event = try makeKeyDownEvent(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        )

        let result = handler(event)

        XCTAssertNil(result, "Handler returned true → local monitor must swallow event")
    }

    /// When the closure declines to handle (pill idle), the local
    /// monitor must return the event unchanged so normal Esc behaviour
    /// (close menu, exit text-field editing) still works.
    func testLocalMonitorPassesThroughEscapeWhenHandlerDeclines() throws {
        var capturedHandler: ((NSEvent) -> NSEvent?)?
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { false },
            installGlobal: { _, _ in nil },
            installLocal: { _, handler in
                capturedHandler = handler
                return "mock-local"
            },
            uninstall: { _ in }
        )

        monitor.start()
        let handler = try XCTUnwrap(capturedHandler)
        let event = try makeKeyDownEvent(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        )

        let result = handler(event)

        XCTAssertNotNil(result, "Handler returned false → local monitor must pass event through")
    }

    /// Non-Esc keys must always pass through the local monitor — we
    /// never swallow events that didn't match the filter.
    func testLocalMonitorPassesThroughNonEscapeKeyCode() throws {
        var capturedHandler: ((NSEvent) -> NSEvent?)?
        let monitor = EscapeKeyMonitor(
            onEscapePressed: { true },
            installGlobal: { _, _ in nil },
            installLocal: { _, handler in
                capturedHandler = handler
                return "mock-local"
            },
            uninstall: { _ in }
        )

        monitor.start()
        let handler = try XCTUnwrap(capturedHandler)
        // keyCode 36 = Return — handle() returns false because it isn't Esc.
        let event = try makeKeyDownEvent(
            keyCode: 36,
            modifierFlags: []
        )

        let result = handler(event)

        XCTAssertNotNil(result, "Non-Esc keys must pass through local monitor unchanged")
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
