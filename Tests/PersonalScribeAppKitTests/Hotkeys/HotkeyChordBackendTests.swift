import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// Registered-chord hotkey backend (macOS hot key API): each configured
/// shortcut is registered with the OS, which delivers only that chord —
/// no system-wide keyboard tap sits in the typing path.
@MainActor
final class HotkeyChordBackendTests: XCTestCase {
    private static let slash: UInt16 = 44
    private static let optionSlash = HotkeyChord(keyCode: slash, modifiers: [.option])

    private var logger: PersonalScribeLogger {
        PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
    }

    private func makeRouter(
        registrar: FakeChordRegistrar,
        tapFactoryCalls: UnsafeMutablePointer<Int>? = nil
    ) -> KeyEventRouter {
        KeyEventRouter(
            tapFactory: { decider in
                tapFactoryCalls?.pointee += 1
                return HotkeyEventTap(decider: decider, installer: { _, _ in nil })
            },
            installLocal: { _, _ in NSObject() },
            installGlobal: { _, _ in NSObject() },
            uninstall: { _ in },
            logger: logger,
            backend: .registeredChords(registrar)
        )
    }

    // MARK: - Router

    func testChordBackendNeverCreatesKeyboardTap() {
        var tapCalls = 0
        let router = withUnsafeMutablePointer(to: &tapCalls) { pointer in
            let router = makeRouter(registrar: FakeChordRegistrar(), tapFactoryCalls: pointer)
            router.start()
            return router
        }
        XCTAssertEqual(tapCalls, 0)
        XCTAssertFalse(router.needsAccessibilityForHotkeys)
    }

    func testRegisteredChordDeliversPressAndReleaseToGlobalDeciders() {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        router.start()
        var seen: [HotkeyEvent.EventType] = []
        let decider = router.registerGlobalDecider { event in
            if event.keyCode == Self.slash { seen.append(event.type) }
            return false
        }
        let registration = router.registerGlobalChord(Self.optionSlash)

        XCTAssertTrue(registration.isRegistered)
        registrar.fire(Self.optionSlash, pressed: true)
        registrar.fire(Self.optionSlash, pressed: false)

        XCTAssertEqual(seen, [.keyDown, .keyUp])
        withExtendedLifetime(decider) {}
    }

    func testDroppingRegistrationUnregistersImmediately() {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        var registration: KeyEventRouterChordRegistration? = router.registerGlobalChord(Self.optionSlash)
        XCTAssertEqual(registrar.registered, [Self.optionSlash])

        registration = nil

        XCTAssertEqual(registrar.registered, [], "unregister must be synchronous so a re-arm can't race it")
        XCTAssertNil(registration)
    }

    func testRefusedChordReportsNotRegistered() {
        let registrar = FakeChordRegistrar()
        registrar.refuse = [Self.optionSlash]
        let router = makeRouter(registrar: registrar)

        XCTAssertFalse(router.registerGlobalChord(Self.optionSlash).isRegistered)
    }

    func testSuspendingChordsReleasesThemUntilResumed() async {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        let registration = router.registerGlobalChord(Self.optionSlash)

        var suspension: KeyEventRouterToken? = router.suspendGlobalChords()
        XCTAssertEqual(registrar.registered, [])

        suspension = nil
        await Task.yield()
        XCTAssertEqual(registrar.registered, [Self.optionSlash])
        XCTAssertNil(suspension)
        withExtendedLifetime(registration) {}
    }

    // MARK: - GlobalHotkeyMonitor

    func testMonitorRegistersRecordingAndModeChordsAndTogglesOnTap() {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        router.start()
        var toggles = 0
        let monitor = GlobalHotkeyMonitor(
            onToggle: { toggles += 1 },
            recordingHotkey: HotkeyPreference(keyCode: Self.slash, tapCount: 1, modifiers: NSEvent.ModifierFlags.option.rawValue),
            router: router,
            logger: logger
        )
        monitor.start()
        let modeChord = HotkeyChord(keyCode: 18, modifiers: [.control, .option])
        monitor.updatePerModeHotkeys([
            WorkflowMode(
                id: "m1",
                name: "Mode",
                hotkey: HotkeyPreference(keyCode: 18, modifiers: modeChord.modifiers.rawValue),
                pipelineShape: .batch,
                processors: [.transcriber(kind: .asr)],
                captureControllers: [.manualHotkey],
                outputSinks: [.frontmostPaste(enabled: .override(true))]
            )
        ])

        XCTAssertEqual(Set(registrar.registered), [Self.optionSlash, modeChord])

        registrar.fire(Self.optionSlash, pressed: true)
        registrar.fire(Self.optionSlash, pressed: false)
        XCTAssertEqual(toggles, 1)
    }

    func testMonitorReRegistersWhenRecordingHotkeyChanges() {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        router.start()
        let monitor = GlobalHotkeyMonitor(onToggle: {}, router: router, logger: logger)
        monitor.start()

        let newChord = HotkeyChord(keyCode: 49, modifiers: [.control])
        monitor.updateRecordingHotkey(HotkeyPreference(keyCode: 49, tapCount: 1, modifiers: newChord.modifiers.rawValue))

        XCTAssertEqual(registrar.registered, [newChord])
    }

    // MARK: - EscapeKeyMonitor

    func testEscapeIsRegisteredOnlyWhileArmed() {
        let registrar = FakeChordRegistrar()
        let router = makeRouter(registrar: registrar)
        router.start()
        var cancels = 0
        let monitor = EscapeKeyMonitor(router: router) {
            cancels += 1
            return true
        }
        monitor.start()
        let esc = HotkeyChord(keyCode: EscapeKeyMonitor.escapeKeyCode, modifiers: [])
        XCTAssertEqual(registrar.registered, [], "Esc must reach other apps when not recording")

        monitor.setArmed(true)
        XCTAssertEqual(registrar.registered, [esc])
        registrar.fire(esc, pressed: true)
        XCTAssertEqual(cancels, 1)

        monitor.setArmed(false)
        XCTAssertEqual(registrar.registered, [])
    }
}

@MainActor
final class FakeChordRegistrar: HotkeyChordRegistering {
    var onEvent: (@MainActor (UInt32, Bool, TimeInterval) -> Void)?
    var refuse: Set<HotkeyChord> = []
    private var byID: [UInt32: HotkeyChord] = [:]
    private var order: [UInt32] = []

    var registered: [HotkeyChord] { order.compactMap { byID[$0] } }

    func register(_ chord: HotkeyChord, id: UInt32) -> Bool {
        guard !refuse.contains(chord) else { return false }
        byID[id] = chord
        order.append(id)
        return true
    }

    func unregister(id: UInt32) {
        byID[id] = nil
        order.removeAll { $0 == id }
    }

    func fire(_ chord: HotkeyChord, pressed: Bool) {
        guard let id = byID.first(where: { $0.value == chord })?.key else { return }
        onEvent?(id, pressed, ProcessInfo.processInfo.systemUptime)
    }
}

@MainActor
final class HotkeyChordRecorderFlowTests: XCTestCase {
    /// Re-recording the same shortcut in Settings: chords are suspended
    /// while the recorder is open, the binding is "updated" to the same
    /// chord, then the recorder closes. The shortcut must work again.
    func testReRecordingSameShortcutLeavesItRegistered() async {
        let registrar = FakeChordRegistrar()
        let logger = PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
        let router = KeyEventRouter(
            installLocal: { _, _ in NSObject() },
            installGlobal: { _, _ in NSObject() },
            uninstall: { _ in },
            logger: logger,
            backend: .registeredChords(registrar)
        )
        router.start()
        let preference = HotkeyPreference(keyCode: 44, modifiers: NSEvent.ModifierFlags.option.rawValue)
        let monitor = GlobalHotkeyMonitor(onToggle: {}, recordingHotkey: preference, router: router, logger: logger)
        monitor.start()

        var suspension: KeyEventRouterToken? = router.suspendGlobalChords()
        monitor.updateRecordingHotkey(preference)
        suspension = nil
        for _ in 0..<5 { await Task.yield() }

        XCTAssertNil(suspension)
        XCTAssertEqual(registrar.registered, [HotkeyChord(preference)])
    }
}

@MainActor
final class HotkeyRecorderChordSuspensionTests: XCTestCase {
    private func makeRouter(_ registrar: FakeChordRegistrar) -> KeyEventRouter {
        KeyEventRouter(
            installLocal: { _, _ in NSObject() },
            installGlobal: { _, _ in NSObject() },
            uninstall: { _ in },
            logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui),
            backend: .registeredChords(registrar)
        )
    }

    /// The sheet's view may outlive its dismissal, so Set / Cancel must
    /// hand the shortcuts back themselves — not wait for the view to go.
    func testSetAndCancelResumeShortcutsWithoutWaitingForTheView() async {
        for finish in [{ (m: HotkeyRecorderModel) in m.confirm() }, { $0.cancel() }] {
            let registrar = FakeChordRegistrar()
            let router = makeRouter(registrar)
            let chord = HotkeyChord(keyCode: 44, modifiers: [.option])
            let registration = router.registerGlobalChord(chord)
            let model = HotkeyRecorderModel(onConfirm: { _ in }, onCancel: {})

            model.attach(to: router)
            XCTAssertEqual(registrar.registered, [], "recorder must capture, not trigger, existing shortcuts")
            _ = try? model.handle(event: HotkeyEvent(
                type: .keyDown, keyCode: 44, modifierFlags: [.option], timestamp: 0, isARepeat: false
            ))
            finish(model)
            for _ in 0..<5 { await Task.yield() }

            XCTAssertEqual(registrar.registered, [chord])
            withExtendedLifetime(registration) {}
        }
    }
}
