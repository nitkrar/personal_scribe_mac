import Combine
import XCTest
@testable import PersonalScribeAppKit
@testable import PersonalScribeCore

/// Tests for `OnboardingCompletionObserver` — watches a
/// `PermissionService` and flips the `OnboardingCompleted`
/// UserDefault to `true` the first time `OnboardingCompletionPolicy`
/// would return `true`. Idempotent — once flipped, stops observing.
///
/// Ticket #015 (minimal scope).
@MainActor
final class OnboardingCompletionObserverTests: XCTestCase {
    private func isolatedDefaults() -> UserDefaults {
        let suiteName = "PersonalScribeTests.OnboardingCompletion.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    /// Fresh install with no permissions granted — observer does not
    /// flip the flag on start.
    func testStartLeavesFlagFalseWhenPermissionsArePending() {
        let defaults = isolatedDefaults()
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
        ])
        let observer = OnboardingCompletionObserver(
            permissionService: service,
            defaults: defaults
        )
        observer.start()

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)
    }

    /// App already has perms (e.g. a previous install, or user granted
    /// via System Settings before launching) — observer flips the flag
    /// immediately on `start()`.
    func testStartFlipsFlagWhenRequiredPermissionsAlreadyGranted() {
        let defaults = isolatedDefaults()
        let service = FakePermissionService(statuses: [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .pending,
        ])
        let observer = OnboardingCompletionObserver(
            permissionService: service,
            defaults: defaults
        )
        observer.start()

        XCTAssertEqual(OnboardingState.resolve(from: defaults), .completed)
    }

    /// User grants perms during the session — observer reacts and
    /// flips the flag.
    func testObserverFlipsFlagWhenPermissionsTransitionToGranted() async {
        let defaults = isolatedDefaults()
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
        ])
        let observer = OnboardingCompletionObserver(
            permissionService: service,
            defaults: defaults
        )
        observer.start()
        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)

        service.nextRefreshStatuses = [
            .microphone: .granted,
            .inputMonitoring: .granted,
        ]
        service.refresh()

        // The observer hops through DispatchQueue.main to mirror the
        // PermissionService adapter's delivery pattern, so let a
        // runloop tick pass before asserting.
        await waitForFlag(in: defaults, to: .completed)
        XCTAssertEqual(OnboardingState.resolve(from: defaults), .completed)
    }

    /// Granting only Accessibility (the optional step) doesn't flip
    /// the flag — required perms remain pending.
    func testOnlyAccessibilityGrantDoesNotFlipFlag() async {
        let defaults = isolatedDefaults()
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ])
        let observer = OnboardingCompletionObserver(
            permissionService: service,
            defaults: defaults
        )
        observer.start()

        service.nextRefreshStatuses = [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .granted,
        ]
        service.refresh()

        // Wait a tick for any potential flip to settle.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(OnboardingState.resolve(from: defaults), .incomplete)
    }

    /// Once the flag is set, subsequent permission changes don't
    /// re-write it — the observer stops after the first flip so a
    /// later revoke doesn't churn the default.
    func testObserverDoesNotReFlipAfterCompletion() async {
        let defaults = isolatedDefaults()
        OnboardingState.completed.persist(to: defaults)
        let service = FakePermissionService(statuses: [
            .microphone: .granted,
            .inputMonitoring: .granted,
        ])
        let observer = OnboardingCompletionObserver(
            permissionService: service,
            defaults: defaults
        )
        observer.start()

        // Flip happens to already be correct — now simulate a revoke
        // from the system. Flag must stay `.completed`.
        service.nextRefreshStatuses = [
            .microphone: .denied,
            .inputMonitoring: .granted,
        ]
        service.refresh()

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertEqual(OnboardingState.resolve(from: defaults), .completed)
    }

    // MARK: - Helpers

    /// Poll the UserDefault until it reaches `target` or we exceed a
    /// generous timeout. Mirrors the PermissionServiceAdapter's
    /// `DispatchQueue.main.async` delivery — the flip reaches disk on
    /// a following runloop tick.
    private func waitForFlag(
        in defaults: UserDefaults,
        to target: OnboardingState,
        timeout: TimeInterval = 1.0
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if OnboardingState.resolve(from: defaults) == target {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

// MARK: - Fake PermissionService

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    var nextRefreshStatuses: [Permission: PermissionStatus]

    init(statuses: [Permission: PermissionStatus]) {
        self.statuses = statuses
        self.nextRefreshStatuses = statuses
    }

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

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {
        statuses = nextRefreshStatuses
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}
