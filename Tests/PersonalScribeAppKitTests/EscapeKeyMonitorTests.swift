import AppKit
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

    /// The observe-only global monitor is the fallback for when macOS
    /// refused the Esc hot key: it still cancels (can't swallow). While
    /// Esc is registered it stays quiet so one press doesn't cancel twice.
    func testObserverFallbackFiresOnlyWhenEscapeIsNotRegistered() {
        let registrar = FakeChordRegistrar()
        let router = makeStubRouter(registrar: registrar)
        var fireCount = 0
        let monitor = EscapeKeyMonitor(router: router) {
            fireCount += 1
            return true
        }
        monitor.start()
        let esc = makeKeyDown(keyCode: EscapeKeyMonitor.escapeKeyCode, modifierFlags: [])

        monitor.setArmed(true)
        router.handleGlobalObserved(esc)
        XCTAssertEqual(fireCount, 0, "registered: the hot key path owns Esc")

        monitor.setArmed(false)
        registrar.refuse = [HotkeyChord(keyCode: EscapeKeyMonitor.escapeKeyCode, modifiers: [])]
        monitor.setArmed(true)
        router.handleGlobalObserved(esc)
        XCTAssertEqual(fireCount, 1, "refused: observer cancels")
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

    /// Stub router: fake chord registrar; NSEvent installers no-op so
    /// tests drive dispatch through the router's test seams.
    private func makeStubRouter(registrar: FakeChordRegistrar = FakeChordRegistrar()) -> KeyEventRouter {
        KeyEventRouter(
            chordRegistrar: registrar,
            installLocal: { _, _ in NSObject() },
            installGlobal: { _, _ in NSObject() },
            uninstall: { _ in }
        )
    }
}
