import AppKit
import CoreGraphics
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `EscapeKeyMonitor`'s filter logic + router wiring (post-#028
/// migration). The filter is exercised directly via `monitor.handle(event:)`
/// using `HotkeyEvent` literals; the router wiring is exercised via a
/// stub `KeyEventRouter` whose `handleLocal` / `handleGlobalObserved`
/// test seams drive the dispatch chain without installing real monitors.
@MainActor
final class EscapeKeyMonitorTests: XCTestCase {

    // MARK: - Filter logic

    /// Plain Esc keyDown → handler fires; decider returns whatever the
    /// handler returns.
    func testPlainEscapeKeyDownFiresCallback() {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: makeStubRouter()) {
            fireCount += 1
            return true
        }

        let result = monitor.handle(event: makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertEqual(fireCount, 1)
        XCTAssertTrue(result)
    }

    /// Spec intent: plain Esc cancels. Modified Esc (Cmd+Esc, Option+Esc,
    /// etc.) is left alone — those are system / app shortcuts we don't
    /// want to intercept.
    func testEscapeWithModifierIsIgnored() {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: makeStubRouter()) {
            fireCount += 1
            return true
        }

        for flags: NSEvent.ModifierFlags in [
            [.command],
            [.option],
            [.control],
            [.shift],
            [.command, .shift],
        ] {
            _ = monitor.handle(event: makeKeyDown(
                keyCode: EscapeKeyMonitor.escapeKeyCode,
                modifierFlags: flags
            ))
        }

        XCTAssertEqual(fireCount, 0)
    }

    func testNonEscapeKeyCodeIsIgnored() {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: makeStubRouter()) {
            fireCount += 1
            return true
        }

        // keyCode 36 = Return
        _ = monitor.handle(event: makeKeyDown(keyCode: 36, modifierFlags: []))

        XCTAssertEqual(fireCount, 0)
    }

    func testNonKeyDownEventIsIgnored() {
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: makeStubRouter()) {
            fireCount += 1
            return true
        }

        let keyUp = HotkeyEvent(
            type: .keyUp,
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: [],
            timestamp: 0,
            isARepeat: false
        )
        _ = monitor.handle(event: keyUp)

        XCTAssertEqual(fireCount, 0)
    }

    // MARK: - Router wiring

    func testStartRegistersLocalDeciderThatSwallowsEscape() {
        let router = makeStubRouter()
        let monitor = EscapeKeyMonitor(router: router) { true }

        monitor.start()

        let swallow = router.handleLocal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertTrue(swallow, "Esc keyDown delivered to Ninimma must be swallowed")
        XCTAssertTrue(monitor.isActive)
    }

    /// Esc during a recording must not reach the frontmost app (it
    /// leaked to terminals / Claude Code as an interrupt). With the CG
    /// tap installed, the monitor is a global *decider* and swallows it.
    func testEscapeIsSwallowedSystemWideWhileRecording() {
        let router = makeStubRouter()
        router.start()
        let monitor = EscapeKeyMonitor(router: router) { true }
        monitor.start()

        let swallowed = router.handleGlobal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertTrue(swallowed)
    }

    /// Outside a recording the handler returns false and Esc passes
    /// through to the focused app untouched.
    func testEscapePassesThroughSystemWideWhenNotRecording() {
        let router = makeStubRouter()
        router.start()
        let monitor = EscapeKeyMonitor(router: router) { false }
        monitor.start()

        let swallowed = router.handleGlobal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertFalse(swallowed)
    }

    /// Without the CG tap (no Accessibility) the observe-only global
    /// monitor is the fallback: it still cancels (can't swallow). With the
    /// tap active it stays quiet so one Esc doesn't cancel twice.
    func testObserverFallbackFiresOnlyWhenTapIsUnavailable() {
        let router = makeStubRouter()
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: router) {
            fireCount += 1
            return true
        }
        monitor.start()
        let esc = makeKeyDown(keyCode: EscapeKeyMonitor.escapeKeyCode, modifierFlags: [])

        router.handleGlobalObserved(esc)
        XCTAssertEqual(fireCount, 1, "no tap: observer cancels")

        router.start()
        router.handleGlobalObserved(esc)
        XCTAssertEqual(fireCount, 1, "tap active: decider path owns Esc")
    }

    func testStartIsIdempotent() {
        let router = makeStubRouter()
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: router) {
            fireCount += 1
            // Pass-through so a doubly-registered decider would
            // re-fire on the same event.
            return false
        }

        monitor.start()
        monitor.start()

        _ = router.handleLocal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))

        XCTAssertEqual(fireCount, 1, "Duplicate start must not register decider twice")
    }

    func testStopUnregistersTokensSoChainNoLongerFires() async {
        let router = makeStubRouter()
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: router) {
            fireCount += 1
            return true
        }
        monitor.start()
        _ = router.handleLocal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))
        XCTAssertEqual(fireCount, 1)

        monitor.stop()
        // Token deinit cleanup is Task-dispatched on MainActor.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)

        _ = router.handleLocal(makeKeyDown(
            keyCode: EscapeKeyMonitor.escapeKeyCode,
            modifierFlags: []
        ))
        XCTAssertEqual(fireCount, 1, "After stop, local decider must not fire")
        XCTAssertFalse(monitor.isActive)
    }

    // MARK: - Helpers

    private func makeKeyDown(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags
    ) -> HotkeyEvent {
        HotkeyEvent(
            type: .keyDown,
            keyCode: keyCode,
            modifierFlags: modifierFlags,
            timestamp: 0,
            isARepeat: false
        )
    }

    /// Stub router whose CG tap install is fake (no real Input
    /// Monitoring permission required). Local + global NSEvent
    /// installers no-op (return a sentinel) so the router's `start()`
    /// is not exercised — tests drive registration through the router's
    /// `handleLocal` / `handleGlobalObserved` test seams.
    private func makeStubRouter() -> KeyEventRouter {
        KeyEventRouter(
            tapFactory: { decider in
                HotkeyEventTap(
                    decider: decider,
                    installer: { _, _ in
                        Self.makeFakePort()
                    }
                )
            },
            installLocal: { _, _ in NSObject() },
            installGlobal: { _, _ in NSObject() },
            uninstall: { _ in }
        )
    }

    private static func makeFakePort() -> CFMachPort {
        var context = CFMachPortContext(
            version: 0,
            info: nil,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        return CFMachPortCreate(nil, { _, _, _, _ in }, &context, nil)!
    }
}
