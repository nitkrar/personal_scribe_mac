import XCTest
@testable import PersonalScribeCore

/// Tests for `OnboardingCompletionPolicy` — the pure predicate that
/// decides when the first-run `OnboardingCompleted` flag should flip
/// to `true` based on the user's permission grants.
///
/// Ticket #015 (minimal scope). Accessibility is optional; Mic +
/// Input Monitoring are required (an app that can't hear you or
/// receive your hotkey is useless).
final class OnboardingCompletionPolicyTests: XCTestCase {
    func testReturnsFalseForEmptyStatuses() {
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: [:]))
    }

    func testReturnsFalseWhenOnlyMicrophoneIsGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsFalseWhenOnlyInputMonitoringIsGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .inputMonitoring: .granted,
            .accessibility: .pending,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsTrueWhenBothRequiredPermissionsAreGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .pending,
        ]
        XCTAssertTrue(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    /// Accessibility is an optional step per the ticket body — it
    /// enables paste-injection but the app can function (clipboard
    /// fallback path) without it. Grant state is irrelevant to the
    /// completion predicate.
    func testAccessibilityGrantDoesNotAffectCompletion() {
        let denied: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .denied,
        ]
        XCTAssertTrue(OnboardingCompletionPolicy.shouldMarkComplete(statuses: denied))

        let granted: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ]
        XCTAssertTrue(OnboardingCompletionPolicy.shouldMarkComplete(statuses: granted))
    }

    func testReturnsFalseWhenRequiredPermissionIsDenied() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .denied,
            .accessibility: .granted,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsFalseWhenRequiredPermissionIsPending() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .pending,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }
}
