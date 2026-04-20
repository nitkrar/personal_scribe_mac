import Combine
import XCTest
@testable import SeshatAppKit
import SeshatCore

@MainActor
final class OnboardingViewModelTests: XCTestCase {
    func testInitialStateStartsWithAllPermissionsPending() {
        let viewModel = OnboardingViewModel(permissionService: FakePermissionService())

        XCTAssertEqual(viewModel.microphoneState, .pending)
        XCTAssertEqual(viewModel.inputMonitoringState, .pending)
        XCTAssertEqual(viewModel.accessibilityState, .pending)
        XCTAssertFalse(viewModel.canContinue)
        XCTAssertFalse(viewModel.isOnboardingComplete)
    }

    func testRequestMicrophoneAccessMarksMicrophoneGranted() async {
        let permissionService = FakePermissionService()
        permissionService.statusUpdatesAfterRequest[.microphone] = .granted
        permissionService.requestOutcomes[.microphone] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .granted
        )
        let viewModel = OnboardingViewModel(permissionService: permissionService)

        await viewModel.requestMicrophoneAccess()

        XCTAssertEqual(viewModel.microphoneState, .granted)
        XCTAssertEqual(viewModel.inputMonitoringState, .pending)
        XCTAssertEqual(viewModel.accessibilityState, .pending)
    }

    func testCanContinueRequiresMicrophoneAndInputMonitoringButNotAccessibility() async {
        let permissionService = FakePermissionService()
        permissionService.statusUpdatesAfterRequest[.microphone] = .granted
        permissionService.statusUpdatesAfterRequest[.inputMonitoring] = .granted
        permissionService.requestOutcomes[.microphone] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .granted
        )
        permissionService.requestOutcomes[.inputMonitoring] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: true,
            finalStatus: .granted
        )
        permissionService.requestOutcomes[.accessibility] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .pending
        )
        let viewModel = OnboardingViewModel(permissionService: permissionService)

        XCTAssertFalse(viewModel.canContinue)

        await viewModel.requestMicrophoneAccess()
        XCTAssertFalse(viewModel.canContinue)

        await viewModel.requestInputMonitoringAccess()
        XCTAssertTrue(viewModel.canContinue)

        await viewModel.requestAccessibilityAccess()
        XCTAssertEqual(viewModel.accessibilityState, .openSettings)
        XCTAssertTrue(viewModel.canContinue)
    }

    func testRequestAccessibilityAccessShowsWarningWhenServiceStillReportsPendingAfterPrompt() async {
        let permissionService = FakePermissionService(
            statuses: [
                .microphone: .granted,
                .inputMonitoring: .granted,
                .accessibility: .pending,
            ]
        )
        permissionService.requestOutcomes[.accessibility] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .pending
        )
        let viewModel = OnboardingViewModel(permissionService: permissionService)

        XCTAssertFalse(viewModel.showsAccessibilityWarning)
        XCTAssertTrue(viewModel.canContinue)

        await viewModel.requestAccessibilityAccess()

        XCTAssertEqual(viewModel.accessibilityState, .openSettings)
        XCTAssertTrue(viewModel.canContinue)
        XCTAssertTrue(viewModel.showsAccessibilityWarning)
    }

    func testRequestInputMonitoringAccessShowsOpenSettingsStateWhenServiceStillReportsPendingAfterPrompt() async {
        let permissionService = FakePermissionService(
            statuses: [
                .microphone: .granted,
                .inputMonitoring: .pending,
                .accessibility: .pending,
            ]
        )
        permissionService.requestOutcomes[.inputMonitoring] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: true,
            finalStatus: .pending
        )
        let viewModel = OnboardingViewModel(permissionService: permissionService)

        await viewModel.requestInputMonitoringAccess()

        XCTAssertEqual(viewModel.inputMonitoringState, .openSettings)
        XCTAssertFalse(viewModel.canContinue)
    }

    func testContinueTappedPersistsCompletionWhenMandatoryPermissionsGranted() async {
        let permissionService = FakePermissionService()
        permissionService.statusUpdatesAfterRequest[.microphone] = .granted
        permissionService.statusUpdatesAfterRequest[.inputMonitoring] = .granted
        permissionService.requestOutcomes[.microphone] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: false,
            finalStatus: .granted
        )
        permissionService.requestOutcomes[.inputMonitoring] = RequestOutcome(
            prompted: true,
            openedSettings: false,
            requiresRelaunch: true,
            finalStatus: .granted
        )
        var didPersistCompletion = false
        let viewModel = OnboardingViewModel(
            permissionService: permissionService,
            persistCompletion: {
                didPersistCompletion = true
            }
        )

        viewModel.continueTapped()
        XCTAssertFalse(didPersistCompletion)
        XCTAssertFalse(viewModel.isOnboardingComplete)

        await viewModel.requestMicrophoneAccess()
        await viewModel.requestInputMonitoringAccess()

        viewModel.continueTapped()

        XCTAssertTrue(didPersistCompletion)
        XCTAssertTrue(viewModel.isOnboardingComplete)
        XCTAssertEqual(viewModel.accessibilityState, .skipped)
    }

    func testSkipSetupTappedPersistsCompletion() {
        var didPersistCompletion = false
        let viewModel = OnboardingViewModel(
            permissionService: FakePermissionService(),
            persistCompletion: {
                didPersistCompletion = true
            }
        )

        viewModel.skipSetupTapped()

        XCTAssertTrue(viewModel.isOnboardingComplete)
        XCTAssertTrue(didPersistCompletion)
    }

    func testSkipAccessibilityMarksWarningStateWithoutBlockingContinue() {
        let viewModel = OnboardingViewModel(
            permissionService: FakePermissionService(
                statuses: [
                    .microphone: .granted,
                    .inputMonitoring: .granted,
                    .accessibility: .pending,
                ]
            )
        )

        viewModel.skipAccessibilityAccess()

        XCTAssertEqual(viewModel.accessibilityState, .skipped)
        XCTAssertTrue(viewModel.canContinue)
    }
}

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    var requestOutcomes: [Permission: RequestOutcome] = [:]
    var statusUpdatesAfterRequest: [Permission: PermissionStatus] = [:]
    var nextRefreshStatuses: [Permission: PermissionStatus]

    init(
        statuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ]
    ) {
        self.statuses = statuses
        self.nextRefreshStatuses = statuses
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        if let updatedStatus = statusUpdatesAfterRequest[permission] {
            statuses[permission] = updatedStatus
        }

        return requestOutcomes[permission]
            ?? RequestOutcome(
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
