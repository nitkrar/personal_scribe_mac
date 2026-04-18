import XCTest
@testable import SeshatAppKit

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testInitialPaneIsWelcome() {
        let viewModel = OnboardingViewModel(permissionProbe: FakePermissionRequester())

        XCTAssertEqual(viewModel.currentPane, .welcome)
        XCTAssertEqual(viewModel.microphoneOutcome, .pending)
        XCTAssertEqual(viewModel.inputMonitoringOutcome, .pending)
        XCTAssertEqual(viewModel.accessibilityOutcome, .pending)
        XCTAssertFalse(viewModel.isOnboardingComplete)
    }

    func testAdvanceMovesFromWelcomeToMicrophone() {
        let viewModel = OnboardingViewModel(permissionProbe: FakePermissionRequester())

        viewModel.advance()

        XCTAssertEqual(viewModel.currentPane, .microphone)
    }

    func testRequestCurrentPermissionMarksMicrophoneGrantedAndAdvances() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(microphoneResult: .granted)
        )
        viewModel.advance()

        await viewModel.requestCurrentPermission()

        XCTAssertEqual(viewModel.microphoneOutcome, .granted)
        XCTAssertEqual(viewModel.currentPane, .inputMonitoring)
    }

    func testRequestCurrentPermissionMarksMicrophoneDeniedAndStaysPut() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(microphoneResult: .denied)
        )
        viewModel.advance()

        await viewModel.requestCurrentPermission()

        XCTAssertEqual(viewModel.microphoneOutcome, .denied)
        XCTAssertEqual(viewModel.currentPane, .microphone)
        XCTAssertFalse(viewModel.isOnboardingComplete)
    }

    func testSkipCurrentPermissionMarksMicrophoneSkippedAndAdvances() {
        let viewModel = OnboardingViewModel(permissionProbe: FakePermissionRequester())
        viewModel.advance()

        viewModel.skipCurrentPermission()

        XCTAssertEqual(viewModel.microphoneOutcome, .skipped)
        XCTAssertEqual(viewModel.currentPane, .inputMonitoring)
    }

    func testResolvingAllPermissionPanesEndsOnDone() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(
                microphoneResult: .granted,
                inputMonitoringResult: .granted,
                accessibilityResult: .granted
            )
        )

        viewModel.advance()
        await viewModel.requestCurrentPermission()
        await viewModel.requestCurrentPermission()
        await viewModel.requestCurrentPermission()

        XCTAssertEqual(viewModel.currentPane, .done)
        XCTAssertEqual(viewModel.microphoneOutcome, .granted)
        XCTAssertEqual(viewModel.inputMonitoringOutcome, .granted)
        XCTAssertEqual(viewModel.accessibilityOutcome, .granted)
        XCTAssertTrue(viewModel.isOnboardingComplete)
    }

    func testSkippingRemainingPermissionsCanAlsoCompleteOnboarding() async {
        let viewModel = OnboardingViewModel(
            permissionProbe: FakePermissionRequester(
                microphoneResult: .granted,
                accessibilityResult: .granted
            )
        )

        viewModel.advance()
        await viewModel.requestCurrentPermission()
        viewModel.skipCurrentPermission()
        await viewModel.requestCurrentPermission()

        XCTAssertEqual(viewModel.currentPane, .done)
        XCTAssertEqual(viewModel.inputMonitoringOutcome, .skipped)
        XCTAssertTrue(viewModel.isOnboardingComplete)
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
