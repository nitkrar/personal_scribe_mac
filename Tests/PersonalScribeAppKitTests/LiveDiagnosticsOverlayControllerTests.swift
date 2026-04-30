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
}

@MainActor
private final class RecordingLiveDiagnosticsPanelBuilder: LiveDiagnosticsOverlayPanelBuilding {
    let panel = RecordingLiveDiagnosticsPanel()

    func makePanel(initialSize: NSSize) -> any LiveDiagnosticsOverlayPaneling {
        panel
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
