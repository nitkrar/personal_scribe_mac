import XCTest
@testable import SeshatAppKit
import SeshatCore

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testInitialStateStartsWithAllPermissionsPending() {
        let viewModel = OnboardingViewModel(permissionProbe: FakePermissionRequester())

        XCTAssertEqual(viewModel.microphoneOutcome, .pending)
        XCTAssertEqual(viewModel.inputMonitoringOutcome, .pending)
        XCTAssertEqual(viewModel.accessibilityOutcome, .pending)
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertFalse(viewModel.isOnboardingComplete)
    }

    func testRequestMicrophoneAccessMarksMicrophoneGranted() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(microphoneResult: .granted)
        )

        await viewModel.requestMicrophoneAccess()

        XCTAssertEqual(viewModel.microphoneOutcome, .granted)
        XCTAssertEqual(viewModel.inputMonitoringOutcome, .pending)
        XCTAssertEqual(viewModel.accessibilityOutcome, .pending)
    }

    func testCanContinueRequiresMicrophoneAndInputMonitoringButNotAccessibility() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(
                microphoneResult: .granted,
                inputMonitoringResult: .granted,
                accessibilityResult: .denied
            )
        )

        XCTAssertFalse(viewModel.canContinue)

        await viewModel.requestMicrophoneAccess()
        XCTAssertFalse(viewModel.canContinue)

        await viewModel.requestInputMonitoringAccess()
        XCTAssertTrue(viewModel.canContinue)

        await viewModel.requestAccessibilityAccess()
        XCTAssertEqual(viewModel.accessibilityOutcome, .denied)
        XCTAssertTrue(viewModel.canContinue)
    }

    func testContinueTappedPersistsCompletionWhenMandatoryPermissionsGranted() async {
        let defaults = isolatedDefaults(for: #function)
        let viewModel = makeViewModel(
            defaults: defaults,
            permissionProbe: FakePermissionRequester(
                microphoneResult: .granted,
                inputMonitoringResult: .granted
            )
        )

        viewModel.continueTapped()
        XCTAssertEqual(SeshatOnboardingCompleted.resolve(from: defaults), .incomplete)
        XCTAssertFalse(viewModel.isOnboardingComplete)

        await viewModel.requestMicrophoneAccess()
        await viewModel.requestInputMonitoringAccess()

        viewModel.continueTapped()

        XCTAssertTrue(viewModel.isOnboardingComplete)
        XCTAssertEqual(viewModel.accessibilityOutcome, .skipped)
        XCTAssertEqual(SeshatOnboardingCompleted.resolve(from: defaults), .completed)
    }

    func testSkipSetupTappedPersistsCompletion() {
        let defaults = isolatedDefaults(for: #function)
        let viewModel = makeViewModel(defaults: defaults)

        viewModel.skipSetupTapped()

        XCTAssertTrue(viewModel.isOnboardingComplete)
        XCTAssertEqual(SeshatOnboardingCompleted.resolve(from: defaults), .completed)
    }

    func testSkipAccessibilityMarksWarningStateWithoutBlockingContinue() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(
                microphoneResult: .granted,
                inputMonitoringResult: .granted
            )
        )

        await viewModel.requestMicrophoneAccess()
        await viewModel.requestInputMonitoringAccess()

        viewModel.skipAccessibilityAccess()

        XCTAssertEqual(viewModel.accessibilityOutcome, .skipped)
        XCTAssertTrue(viewModel.canContinue)
    }

    private func makeViewModel(
        defaults: UserDefaults,
        permissionProbe: any OnboardingPermissionProbing = FakePermissionRequester()
    ) -> OnboardingViewModel {
        OnboardingViewModel(
            permissionProbe: permissionProbe,
            persistCompletion: {
                SeshatOnboardingCompleted.completed.persist(to: defaults)
            }
        )
    }

    private func isolatedDefaults(for testName: String) -> UserDefaults {
        let suiteName = "OnboardingViewModelTests.\(testName)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }
}

private actor FakePermissionRequester: OnboardingPermissionProbing {
    let microphoneResult: OnboardingPermissionOutcome
    let inputMonitoringResult: OnboardingPermissionOutcome
    let accessibilityResult: OnboardingPermissionOutcome

    init(
        microphoneResult: OnboardingPermissionOutcome = .granted,
        inputMonitoringResult: OnboardingPermissionOutcome = .granted,
        accessibilityResult: OnboardingPermissionOutcome = .granted
    ) {
        self.microphoneResult = microphoneResult
        self.inputMonitoringResult = inputMonitoringResult
        self.accessibilityResult = accessibilityResult
    }

    func requestMicrophoneAccess() async -> OnboardingPermissionOutcome {
        microphoneResult
    }

    func requestInputMonitoringAccess() async -> OnboardingPermissionOutcome {
        inputMonitoringResult
    }

    func requestAccessibilityAccess() async -> OnboardingPermissionOutcome {
        accessibilityResult
    }
}
