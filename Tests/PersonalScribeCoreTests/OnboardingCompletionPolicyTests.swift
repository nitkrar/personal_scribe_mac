import XCTest
@testable import PersonalScribeCore

/// Tests for `OnboardingCompletionPolicy` — the pure predicate that
/// decides when the first-run `OnboardingCompleted` flag should flip
/// to `true` based on the user's permission grants.
///
/// Microphone enables recording; Accessibility enables auto-paste.
/// Registered global hotkeys require neither permission.
final class OnboardingCompletionPolicyTests: XCTestCase {
    func testReturnsFalseForEmptyStatuses() {
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: [:]))
    }

    func testReturnsFalseWhenOnlyMicrophoneIsGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .accessibility: .pending,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsFalseWhenOnlyAccessibilityIsGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .accessibility: .granted,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsTrueWhenMicrophoneAndAccessibilityAreGranted() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .accessibility: .granted,
        ]
        XCTAssertTrue(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }

    func testReturnsFalseWhenMicrophoneIsDenied() {
        let statuses: [Permission: PermissionStatus] = [
            .microphone: .denied,
            .accessibility: .granted,
        ]
        XCTAssertFalse(OnboardingCompletionPolicy.shouldMarkComplete(statuses: statuses))
    }
}
