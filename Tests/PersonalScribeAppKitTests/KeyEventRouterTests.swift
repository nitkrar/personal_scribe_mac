import AppKit
import XCTest
@testable import PersonalScribeAppKit

/// #028 — `KeyEventRouter` registration + dispatch contract. Tests use
/// the `handleLocal` / `handleGlobal` / `handleGlobalObserved` test
/// seams to drive the chain without installing OS hot-key registrations
/// or NSEvent monitors. Lifecycle is covered using injected installers.
@MainActor
final class KeyEventRouterTests: XCTestCase {

    // MARK: - Fixtures

    private func makeEvent(keyCode: UInt16 = 0) -> HotkeyEvent {
        HotkeyEvent(
            type: .keyDown,
            keyCode: keyCode,
            modifierFlags: [],
            timestamp: 0,
            isARepeat: false
        )
    }

    private func makeRouter(
        localInstaller: @escaping KeyEventRouter.LocalInstaller = { _, _ in NSObject() },
        globalInstaller: @escaping KeyEventRouter.GlobalInstaller = { _, _ in NSObject() }
    ) -> KeyEventRouter {
        KeyEventRouter(
            installLocal: localInstaller,
            installGlobal: globalInstaller,
            uninstall: { _ in }
        )
    }

    // MARK: - Local-decider chain

    func testLocalDecidersDispatchInRegistrationOrder() {
        let router = makeRouter()
        var fired: [Int] = []
        let token1 = router.registerLocalDecider { _ in
            fired.append(1)
            return false
        }
        let token2 = router.registerLocalDecider { _ in
            fired.append(2)
            return false
        }
        defer { _ = (token1, token2) }

        let swallowed = router.handleLocal(makeEvent())

        XCTAssertEqual(fired, [1, 2], "Local deciders fire in registration order")
        XCTAssertFalse(swallowed, "Pass-through when no decider returns true")
    }

    func testLocalDeciderSwallowingShortCircuitsChain() {
        let router = makeRouter()
        var fired: [Int] = []
        let token1 = router.registerLocalDecider { _ in
            fired.append(1)
            return true // swallow
        }
        let token2 = router.registerLocalDecider { _ in
            fired.append(2)
            return false
        }
        defer { _ = (token1, token2) }

        let swallowed = router.handleLocal(makeEvent())

        XCTAssertEqual(fired, [1], "Chain short-circuits on first swallow")
        XCTAssertTrue(swallowed)
    }

    func testRegisterLocalDeciderFirstInsertsAtHeadOfChain() {
        // HotkeyRecorder use case: while the recorder UI is open, its
        // chord-capture must take priority over GlobalHotkeyMonitor
        // (already registered). `position: .first` inserts at the front.
        let router = makeRouter()
        var fired: [Int] = []
        let normal = router.registerLocalDecider { _ in
            fired.append(1)
            return false
        }
        let modal = router.registerLocalDecider({ _ in
            fired.append(2)
            return true // swallow
        }, position: .first)
        defer { _ = (normal, modal) }

        let swallowed = router.handleLocal(makeEvent())

        XCTAssertEqual(fired, [2], "First-position decider fires before existing chain")
        XCTAssertTrue(swallowed)
    }

    // MARK: - Token RAII

    func testDroppingTokenUnregistersDecider() async {
        let router = makeRouter()
        var fired = 0
        do {
            let token = router.registerLocalDecider { _ in
                fired += 1
                return false
            }
            _ = router.handleLocal(makeEvent())
            XCTAssertEqual(fired, 1, "Decider fires while token is alive")
            _ = token
        }
        // Token deinit runs cleanup via Task — wait for it to land.
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)

        _ = router.handleLocal(makeEvent())
        XCTAssertEqual(fired, 1, "Decider does not fire after token deallocates")
    }

    // MARK: - Global-decider chain (CG tap path)

    func testGlobalDecidersDispatchInRegistrationOrderAndShortCircuitOnSwallow() {
        let router = makeRouter()
        var fired: [Int] = []
        let token1 = router.registerGlobalDecider { _ in
            fired.append(1)
            return false
        }
        let token2 = router.registerGlobalDecider { _ in
            fired.append(2)
            return true
        }
        let token3 = router.registerGlobalDecider { _ in
            fired.append(3)
            return false
        }
        defer { _ = (token1, token2, token3) }

        let swallowed = router.handleGlobal(makeEvent())

        XCTAssertEqual(fired, [1, 2], "Stops at first swallow")
        XCTAssertTrue(swallowed)
    }

    // MARK: - Global-observer chain (NSEvent global path)

    func testGlobalObserversAllFireRegardlessOfReturn() {
        let router = makeRouter()
        var fired: [Int] = []
        let token1 = router.registerGlobalObserver { _ in
            fired.append(1)
        }
        let token2 = router.registerGlobalObserver { _ in
            fired.append(2)
        }
        defer { _ = (token1, token2) }

        router.handleGlobalObserved(makeEvent())

        XCTAssertEqual(fired, [1, 2], "Observers don't short-circuit; all run")
    }

    // MARK: - Channel isolation

    func testLocalAndGlobalChannelsAreIndependent() {
        let router = makeRouter()
        var localFired = 0
        var globalFired = 0
        let local = router.registerLocalDecider { _ in
            localFired += 1
            return false
        }
        let global = router.registerGlobalDecider { _ in
            globalFired += 1
            return false
        }
        defer { _ = (local, global) }

        _ = router.handleLocal(makeEvent())
        XCTAssertEqual(localFired, 1)
        XCTAssertEqual(globalFired, 0, "Local dispatch must not invoke global deciders")

        _ = router.handleGlobal(makeEvent())
        XCTAssertEqual(localFired, 1, "Global dispatch must not invoke local deciders")
        XCTAssertEqual(globalFired, 1)
    }

    // MARK: - Lifecycle

    func testStartInstallsMonitorsAndStopRemovesThem() {
        let router = makeRouter()

        router.start()
        XCTAssertTrue(router.isActive)

        router.stop()
        XCTAssertFalse(router.isActive)
    }
}
