import AppKit
import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

@MainActor
final class LiveDiagnosticsOverlayControllerTests: XCTestCase {
    func testControllerShowsPanelWhenVerboseOverlayEnabled() {
        let defaults = isolatedDefaults()
        DiagnosticLoggingMode.verbose.persist(to: defaults)
        ShowLiveDiagnosticsOverlayPreference.persist(true, to: defaults)
        let store = DiagnosticsStore(capacity: 5)
        let panelBuilder = RecordingLiveDiagnosticsPanelBuilder()

        let controller = LiveDiagnosticsOverlayController(
            store: store,
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            panelBuilder: panelBuilder
        )

        XCTAssertTrue(controller.isPanelVisible)
        XCTAssertEqual(panelBuilder.panel.orderFrontCallCount, 1)
        _ = controller
    }

    func testControllerHidesPanelWhenPreferencesDisableOverlay() async throws {
        let defaults = isolatedDefaults()
        DiagnosticLoggingMode.verbose.persist(to: defaults)
        ShowLiveDiagnosticsOverlayPreference.persist(true, to: defaults)
        let notificationCenter = NotificationCenter()
        let panelBuilder = RecordingLiveDiagnosticsPanelBuilder()

        let controller = LiveDiagnosticsOverlayController(
            store: DiagnosticsStore(capacity: 5),
            defaults: defaults,
            notificationCenter: notificationCenter,
            panelBuilder: panelBuilder
        )
        XCTAssertTrue(controller.isPanelVisible)

        DiagnosticLoggingMode.errorsOnly.persist(to: defaults)
        notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)

        try await waitForCondition {
            panelBuilder.panel.orderOutCallCount == 1
        }
        XCTAssertFalse(controller.isPanelVisible)
    }

    func testDismissActionFlipsShowOverlayPreferenceAndHidesPanel() async throws {
        let defaults = isolatedDefaults()
        DiagnosticLoggingMode.verbose.persist(to: defaults)
        ShowLiveDiagnosticsOverlayPreference.persist(true, to: defaults)
        let notificationCenter = NotificationCenter()
        let panelBuilder = RecordingLiveDiagnosticsPanelBuilder()

        let controller = LiveDiagnosticsOverlayController(
            store: DiagnosticsStore(capacity: 5),
            defaults: defaults,
            notificationCenter: notificationCenter,
            panelBuilder: panelBuilder
        )
        XCTAssertTrue(controller.isPanelVisible)

        let dismissAction = try XCTUnwrap(panelBuilder.lastDismissAction)
        dismissAction()

        XCTAssertFalse(ShowLiveDiagnosticsOverlayPreference.resolve(from: defaults))

        notificationCenter.post(name: UserDefaults.didChangeNotification, object: defaults)

        try await waitForCondition {
            panelBuilder.panel.orderOutCallCount == 1
        }
        XCTAssertFalse(controller.isPanelVisible)
    }

    func testViewModelDismissActionMatchesPanelDismissAction() async throws {
        let defaults = isolatedDefaults()
        DiagnosticLoggingMode.verbose.persist(to: defaults)
        ShowLiveDiagnosticsOverlayPreference.persist(true, to: defaults)
        let panelBuilder = RecordingLiveDiagnosticsPanelBuilder()

        let controller = LiveDiagnosticsOverlayController(
            store: DiagnosticsStore(capacity: 5),
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            panelBuilder: panelBuilder
        )

        controller.viewModel.dismissAction()

        XCTAssertFalse(ShowLiveDiagnosticsOverlayPreference.resolve(from: defaults))
        _ = controller
    }

    func testClearWipesEventsAndFiltersSubsequentUpdatesByCutoff() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let oldA = makeEventTS(timestamp: Date(timeIntervalSince1970: 100), message: "A")
        let oldB = makeEventTS(timestamp: Date(timeIntervalSince1970: 200), message: "B")
        let newC = makeEventTS(timestamp: Date(timeIntervalSince1970: 300), message: "C")

        // Store delivers newest-first.
        viewModel.update(events: [oldB, oldA])
        XCTAssertEqual(viewModel.events.map { $0.message }, ["B", "A"])

        viewModel.clear()
        XCTAssertTrue(viewModel.events.isEmpty)

        // Store re-emits the unchanged ring buffer; cutoff must filter the
        // already-seen events out so they don't reappear.
        viewModel.update(events: [oldB, oldA])
        XCTAssertTrue(viewModel.events.isEmpty)

        // Genuinely new events past the cutoff become visible.
        viewModel.update(events: [newC, oldB, oldA])
        XCTAssertEqual(viewModel.events.map { $0.message }, ["C"])
    }

    func testEmptySearchTextReturnsAllEvents() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let event = makeEventTS(timestamp: Date(timeIntervalSince1970: 100), message: "msg")
        viewModel.update(events: [event])

        XCTAssertEqual(viewModel.filteredEvents.count, 1)
    }

    func testSearchMatchesMessageSubstringCaseInsensitively() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let foo = makeEventTS(timestamp: Date(timeIntervalSince1970: 100), message: "Foo happened")
        let bar = makeEventTS(timestamp: Date(timeIntervalSince1970: 200), message: "bar happened")
        viewModel.update(events: [bar, foo])

        viewModel.searchText = "foo"

        XCTAssertEqual(viewModel.filteredEvents.map { $0.message }, ["Foo happened"])
    }

    func testSearchMatchesCategory() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let audioEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 100),
            level: .info,
            category: PersonalScribeLogCategory.audio,
            message: "neutral",
            metadata: [:]
        )
        let sessionEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 200),
            level: .info,
            category: PersonalScribeLogCategory.session,
            message: "neutral",
            metadata: [:]
        )
        viewModel.update(events: [sessionEvent, audioEvent])

        viewModel.searchText = "audio"

        XCTAssertEqual(viewModel.filteredEvents.map { $0.category }, ["audio"])
    }

    func testSearchMatchesLevelLabel() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let infoEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 100),
            level: .info,
            category: "neutral",
            message: "neutral",
            metadata: [:]
        )
        let errorEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 200),
            level: .error,
            category: "neutral",
            message: "neutral",
            metadata: [:]
        )
        viewModel.update(events: [errorEvent, infoEvent])

        viewModel.searchText = "ERROR"

        XCTAssertEqual(viewModel.filteredEvents.map { $0.level }, [.error])
    }

    func testSearchMatchesMetadataValue() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let outputEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 100),
            level: .info,
            category: "neutral",
            message: "neutral",
            metadata: ["stage": "output"]
        )
        let captureEvent = makeEventFull(
            timestamp: Date(timeIntervalSince1970: 200),
            level: .info,
            category: "neutral",
            message: "neutral",
            metadata: ["stage": "capture"]
        )
        viewModel.update(events: [captureEvent, outputEvent])

        viewModel.searchText = "output"

        XCTAssertEqual(viewModel.filteredEvents.count, 1)
        XCTAssertEqual(viewModel.filteredEvents.first?.metadata["stage"], "output")
    }

    func testSearchComposesWithClearCutoff() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let oldFoo = makeEventTS(timestamp: Date(timeIntervalSince1970: 100), message: "Foo old")
        let oldBar = makeEventTS(timestamp: Date(timeIntervalSince1970: 200), message: "Bar old")
        let newFoo = makeEventTS(timestamp: Date(timeIntervalSince1970: 300), message: "Foo new")
        viewModel.update(events: [oldBar, oldFoo])
        viewModel.clear()

        viewModel.update(events: [newFoo, oldBar, oldFoo])
        viewModel.searchText = "foo"

        XCTAssertEqual(viewModel.filteredEvents.map { $0.message }, ["Foo new"])
    }

    func testClearOnEmptyViewModelFiltersAnyOlderEventsViaNowCutoff() {
        let viewModel = LiveDiagnosticsOverlayViewModel()
        let stale = makeEventTS(timestamp: Date(timeIntervalSince1970: 1), message: "stale")

        viewModel.clear()
        viewModel.update(events: [stale])

        XCTAssertTrue(viewModel.events.isEmpty)
    }

    func testControllerStreamsDiagnosticsIntoViewModel() async throws {
        let defaults = isolatedDefaults()
        let store = DiagnosticsStore(capacity: 5)
        let controller = LiveDiagnosticsOverlayController(
            store: store,
            defaults: defaults,
            notificationCenter: NotificationCenter(),
            panelBuilder: RecordingLiveDiagnosticsPanelBuilder()
        )

        await store.append(makeEvent(message: "Captured diagnostics"))

        try await waitForCondition {
            controller.currentEvents.count == 1
        }
        XCTAssertEqual(controller.currentEvents.first?.message, "Captured diagnostics")
    }

    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "LiveDiagnosticsOverlayControllerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func waitForCondition(
        timeout: Duration = .seconds(1),
        pollInterval: Duration = .milliseconds(10),
        condition: @escaping @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        XCTFail("Timed out waiting for condition")
    }

    private func makeEvent(message: String) -> RedactedDiagnosticsEvent {
        RedactedDiagnosticsEvent(
            level: .info,
            category: PersonalScribeLogCategory.ui,
            message: message,
            timestamp: Date(timeIntervalSince1970: 123),
            underlyingError: nil,
            metadata: ["stage": PipelineStepID.output.rawValue],
            userFacing: nil,
            sourceLocation: DiagnosticsSourceLocation(
                file: "LiveDiagnosticsOverlayControllerTests.swift",
                function: #function,
                line: #line
            )
        )
    }

    private func makeEventTS(timestamp: Date, message: String) -> RedactedDiagnosticsEvent {
        RedactedDiagnosticsEvent(
            level: .info,
            category: PersonalScribeLogCategory.ui,
            message: message,
            timestamp: timestamp,
            underlyingError: nil,
            metadata: [:],
            userFacing: nil,
            sourceLocation: DiagnosticsSourceLocation(
                file: "LiveDiagnosticsOverlayControllerTests.swift",
                function: #function,
                line: #line
            )
        )
    }

    private func makeEventFull(
        timestamp: Date,
        level: DiagnosticsLevel,
        category: String,
        message: String,
        metadata: [String: String]
    ) -> RedactedDiagnosticsEvent {
        RedactedDiagnosticsEvent(
            level: level,
            category: category,
            message: message,
            timestamp: timestamp,
            underlyingError: nil,
            metadata: metadata,
            userFacing: nil,
            sourceLocation: DiagnosticsSourceLocation(
                file: "LiveDiagnosticsOverlayControllerTests.swift",
                function: #function,
                line: #line
            )
        )
    }
}

@MainActor
private final class RecordingLiveDiagnosticsPanelBuilder: LiveDiagnosticsOverlayPanelBuilding {
    let panel = RecordingLiveDiagnosticsPanel()
    private(set) var lastDismissAction: (() -> Void)?

    func makePanel(
        initialSize: NSSize,
        dismissAction: @escaping () -> Void
    ) -> any LiveDiagnosticsOverlayPaneling {
        lastDismissAction = dismissAction
        return panel
    }
}

@MainActor
private final class RecordingLiveDiagnosticsPanel: LiveDiagnosticsOverlayPaneling {
    var isVisible = false
    private(set) var orderFrontCallCount = 0
    private(set) var orderOutCallCount = 0
    private(set) var contentViews: [NSView] = []

    func orderFrontRegardless() {
        orderFrontCallCount += 1
        isVisible = true
    }

    func orderOut(_ sender: Any?) {
        orderOutCallCount += 1
        isVisible = false
    }

    func setFrameOrigin(_ point: NSPoint) {}

    func setContentSize(_ size: NSSize) {}

    func setContentView(_ view: NSView) {
        contentViews.append(view)
    }
}
