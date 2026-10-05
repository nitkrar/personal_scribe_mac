import AppKit
import Combine
import PersonalScribeAudio
import PersonalScribeCore
@testable import PersonalScribeSession
import XCTest
@testable import PersonalScribeAppKit

/// Tests for `UnifiedWindowController` — bug #041 regression guards
/// covering window-space pinning + main-screen placement.
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

    /// Following the active Space permanently makes macOS treat the window
    /// as not part of any desktop, so it gets buried on return (#101); the
    /// flag is only applied while opening (#041).
    func testWindowFollowsTheActiveSpaceOnlyWhileOpening() async throws {
        let controller = Self.makeController()
        let window = try XCTUnwrap(controller.window)
        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))

        controller.showWindow(nil)
        try await Task.sleep(for: .milliseconds(50))

        XCTAssertFalse(window.collectionBehavior.contains(.moveToActiveSpace))
        window.close()
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

    // MARK: - Main-screen placement

    func testFrameForShowingReturnsSameFrameWhenFullyInsideMainScreen() {
        let mainScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let window = NSRect(x: 200, y: 200, width: 800, height: 600)
        XCTAssertEqual(
            UnifiedWindowController.frameForShowing(
                window,
                mainScreenVisibleFrame: mainScreen
            ),
            window
        )
    }

    func testFrameForShowingCentersWindowThatIsNotFullyInsideMainScreen() {
        let mainScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let partiallyOutsideWindow = NSRect(x: 1500, y: 200, width: 800, height: 600)

        let frame = UnifiedWindowController.frameForShowing(
            partiallyOutsideWindow,
            mainScreenVisibleFrame: mainScreen
        )

        XCTAssertEqual(frame.size, partiallyOutsideWindow.size)
        XCTAssertEqual(frame.midX, mainScreen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, mainScreen.midY, accuracy: 0.5)
    }

    func testFrameForShowingCentersWindowOutsideMainScreen() {
        let mainScreen = NSRect(x: 0, y: 0, width: 1920, height: 1080)
        let strandedWindow = NSRect(x: -2000, y: -2000, width: 800, height: 600)

        let frame = UnifiedWindowController.frameForShowing(
            strandedWindow,
            mainScreenVisibleFrame: mainScreen
        )

        XCTAssertEqual(frame.size, strandedWindow.size)
        XCTAssertEqual(frame.midX, mainScreen.midX, accuracy: 0.5)
        XCTAssertEqual(frame.midY, mainScreen.midY, accuracy: 0.5)
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
            metricsStore: MetricsSnapshotStore(
                reader: StubMetricsReader(),
                logger: PersonalScribeLogger.testing(category: PersonalScribeLogCategory.ui)
            ),
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
