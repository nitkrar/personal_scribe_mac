import AppKit
import Combine
import PersonalScribeAudio
import PersonalScribeCore
@testable import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `UnifiedWindowController` — bug #041 regression guards
/// covering window-space pinning + off-screen-frame reconciliation.
@MainActor
final class UnifiedWindowControllerTests: XCTestCase {

    // MARK: - Foreground recovery state

    func testForegroundRecoveryArmsWhenVisibleWindowWasFrontmostOnDeactivate() {
        var state = UnifiedWindowForegroundRecoveryState()

        state.appDidResignActive(
            unifiedWindowIsVisible: true,
            unifiedWindowIsKey: true,
            unifiedWindowIsMain: false
        )

        XCTAssertTrue(
            state.consumeRestoreRequest(
                appIsActive: true,
                unifiedWindowIsVisible: true
            ),
            "A visible unified window that was key before app deactivation "
            + "must request one foreground recovery on return."
        )
    }

    func testForegroundRecoveryDoesNotArmForBackgroundWindow() {
        var state = UnifiedWindowForegroundRecoveryState()

        state.appDidResignActive(
            unifiedWindowIsVisible: true,
            unifiedWindowIsKey: false,
            unifiedWindowIsMain: false
        )

        XCTAssertFalse(
            state.consumeRestoreRequest(
                appIsActive: true,
                unifiedWindowIsVisible: true
            ),
            "A merely visible background window must not be pulled to the "
            + "front on a later space/app activation."
        )
    }

    func testForegroundRecoveryWaitsUntilAppIsActive() {
        var state = UnifiedWindowForegroundRecoveryState()

        state.appDidResignActive(
            unifiedWindowIsVisible: true,
            unifiedWindowIsKey: false,
            unifiedWindowIsMain: true
        )

        XCTAssertFalse(
            state.consumeRestoreRequest(
                appIsActive: false,
                unifiedWindowIsVisible: true
            ),
            "Space-change notifications while the app is inactive must not "
            + "steal focus back."
        )

        XCTAssertTrue(
            state.consumeRestoreRequest(
                appIsActive: true,
                unifiedWindowIsVisible: true
            ),
            "The pending recovery should remain armed until the app becomes "
            + "active again."
        )
    }

    func testForegroundRecoveryClearsAfterSingleUse() {
        var state = UnifiedWindowForegroundRecoveryState()

        state.appDidResignActive(
            unifiedWindowIsVisible: true,
            unifiedWindowIsKey: true,
            unifiedWindowIsMain: false
        )

        XCTAssertTrue(
            state.consumeRestoreRequest(
                appIsActive: true,
                unifiedWindowIsVisible: true
            )
        )
        XCTAssertFalse(
            state.consumeRestoreRequest(
                appIsActive: true,
                unifiedWindowIsVisible: true
            ),
            "Foreground recovery should be single-shot; once the window has "
            + "been reasserted, later notifications should no-op."
        )
    }

    // MARK: - Bug #041 regression guards — collectionBehavior must not
    // inherit pill-overlay pinning flags, and MUST include
    // `.moveToActiveSpace` so the window follows the user to the current
    // space instead of warping them to the space it was last shown on.

    func testWindowCollectionBehaviorIncludesMoveToActiveSpace() {
        let controller = Self.makeController()
        guard let behavior = controller.window?.collectionBehavior else {
            return XCTFail("Unified window must exist after init")
        }
        XCTAssertTrue(
            behavior.contains(.moveToActiveSpace),
            "Unified window must set `.moveToActiveSpace` so it follows the "
            + "user to the current space (bug #041)."
        )
    }

    func testWindowCollectionBehaviorDoesNotPinLikePillOverlay() {
        let controller = Self.makeController()
        guard let behavior = controller.window?.collectionBehavior else {
            return XCTFail("Unified window must exist after init")
        }
        // These are the pill-overlay panel's pinning flags
        // (PillOverlayPresenter.swift:253). If the unified window ever
        // picks them up via copy-paste, the exact bug #041 symptom
        // returns — the window becomes stationary on the first space
        // it appears on and re-opens there forever.
        XCTAssertFalse(
            behavior.contains(.canJoinAllSpaces),
            "Unified window must NOT set `.canJoinAllSpaces` — that's a "
            + "pill-overlay pinning flag (bug #041)."
        )
        XCTAssertFalse(
            behavior.contains(.stationary),
            "Unified window must NOT set `.stationary` — that's a "
            + "pill-overlay pinning flag (bug #041)."
        )
    }

    // MARK: - Pure-function tests for `reconciledFrame(for:activeScreenVisibleFrame:)`

    func testReconciledFrameReturnsSameFrameWhenMidpointInsideActiveScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 200, y: 200, width: 800, height: 600)
        XCTAssertEqual(
            UnifiedWindowController.reconciledFrame(
                for: window,
                activeScreenVisibleFrame: screen
            ),
            window
        )
    }

    func testReconciledFrameCentersOverActiveScreenWhenMidpointOffscreen() {
        // Simulate: saved window frame lives on a former full-screen
        // space / disconnected monitor at (-2000, -2000). Active screen
        // is a single 1920x1080 display at origin.
        let activeScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let strandedWindow = NSRect(x: -2000, y: -2000, width: 800, height: 600)

        let reconciled = UnifiedWindowController.reconciledFrame(
            for: strandedWindow,
            activeScreenVisibleFrame: activeScreen
        )

        // Size preserved.
        XCTAssertEqual(reconciled.size, strandedWindow.size)
        // Centered on the active screen.
        XCTAssertEqual(reconciled.midX, activeScreen.midX, accuracy: 0.5)
        XCTAssertEqual(reconciled.midY, activeScreen.midY, accuracy: 0.5)
        // Midpoint is now inside the active screen.
        XCTAssertTrue(activeScreen.contains(NSPoint(x: reconciled.midX, y: reconciled.midY)))
    }

    func testReconciledFrameCentersOnMultiMonitorSecondaryDisplay() {
        // User drags cursor to a secondary display on the right; the
        // saved window frame is stranded on the primary display.
        let secondaryScreen = NSRect(x: 1920, y: 0, width: 2560, height: 1440)
        let strandedWindow = NSRect(x: 100, y: 100, width: 800, height: 600)

        let reconciled = UnifiedWindowController.reconciledFrame(
            for: strandedWindow,
            activeScreenVisibleFrame: secondaryScreen
        )

        XCTAssertEqual(reconciled.midX, secondaryScreen.midX, accuracy: 0.5)
        XCTAssertEqual(reconciled.midY, secondaryScreen.midY, accuracy: 0.5)
    }

    func testReconciledFrameReturnsOriginalWhenNoScreenAvailable() {
        // Defensive: if AppKit reports no active screen (headless CI,
        // transient display reconfiguration) we must not produce a
        // NaN-centered frame — pass through unchanged.
        let window = NSRect(x: 100, y: 200, width: 800, height: 600)
        XCTAssertEqual(
            UnifiedWindowController.reconciledFrame(
                for: window,
                activeScreenVisibleFrame: .zero
            ),
            window
        )
    }

    // MARK: - Helpers

    @MainActor
    private static func makeController() -> UnifiedWindowController {
        let defaults = ephemeralDefaults()
        let modelService = ActiveModelService(
            activeIDsPreference: Preference<[ModelKind: String]>(
                key: ActiveModelService.preferenceKey,
                default: [:],
                defaults: defaults
            ),
            isDownloaded: { _ in false },
            download: { _, _ in }
        )
        return UnifiedWindowController(
            defaults: defaults,
            transcriptReader: StubTranscriptReader(),
            metricsReader: StubMetricsReader(),
            permissionService: StubPermissionService(),
            inputDeviceProvider: NoOpAudioInputDeviceProvider(),
            modelService: modelService
        )
    }

    private static func ephemeralDefaults() -> UserDefaults {
        let name = "UnifiedWindowControllerTests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name) ?? .standard
        suite.removePersistentDomain(forName: name)
        return suite
    }
}

// MARK: - Stub dependencies

private struct StubTranscriptReader: TranscriptReading {
    func recent(limit: Int) async -> [TranscriptEntry] { [] }
    func search(query: String) async -> [TranscriptEntry] { [] }
    func all() async -> [TranscriptEntry] { [] }
}

private struct StubMetricsReader: MetricsReading {
    func loadSnapshot(window: MetricsWindow, recentLimit: Int) async throws -> MetricsSnapshot {
        MetricsSnapshot(
            rollups: MetricsRollups.empty(window: window),
            recentTranscriptions: [],
            lastUpdatedAt: Date(),
            lastRefreshReason: .initialLoad
        )
    }

    func recentTranscriptions(limit: Int) async throws -> [TranscriptEntry] { [] }
}

@MainActor
private final class StubPermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus] = [
        .microphone: .granted,
        .inputMonitoring: .granted,
        .accessibility: .granted,
    ]

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        RequestOutcome(
            prompted: false,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] { statuses }

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}
