import Combine
import Foundation
import XCTest
@testable import PersonalScribeAppKit
import PersonalScribeCore

@MainActor
final class PermissionsSubTabViewModelTests: XCTestCase {
    // MARK: - Init / status observation

    func testInitializesStatusesFromService() {
        let service = FakePermissionService(statuses: [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ])

        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(viewModel.statuses[.microphone], .granted)
        XCTAssertEqual(viewModel.statuses[.inputMonitoring], .granted)
        XCTAssertEqual(viewModel.statuses[.accessibility], .granted)
    }

    func testStatusAccessorReadsFromStatuses() {
        let service = FakePermissionService(statuses: [
            .microphone: .granted,
            .inputMonitoring: .denied,
            .accessibility: .pending,
        ])

        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(viewModel.status(for: .microphone), .granted)
        XCTAssertEqual(viewModel.status(for: .inputMonitoring), .denied)
        XCTAssertEqual(viewModel.status(for: .accessibility), .pending)
    }

    func testStatusAccessorReturnsPendingWhenMissing() {
        let service = FakePermissionService(statuses: [:])

        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(viewModel.status(for: .microphone), .pending)
        XCTAssertEqual(viewModel.status(for: .inputMonitoring), .pending)
        XCTAssertEqual(viewModel.status(for: .accessibility), .pending)
    }

    func testStatusUpdatesWhenServicePublishes() {
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ])
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(viewModel.status(for: .microphone), .pending)

        service.updateStatuses([
            .microphone: .granted,
            .inputMonitoring: .denied,
            .accessibility: .pending,
        ])

        // `objectWillChange` handler defers the snapshot read to the
        // next runloop tick, so drain the main queue before asserting.
        drainMainQueue()

        XCTAssertEqual(viewModel.status(for: .microphone), .granted)
        XCTAssertEqual(viewModel.status(for: .inputMonitoring), .denied)
        XCTAssertEqual(viewModel.status(for: .accessibility), .pending)
    }

    // MARK: - Refresh on tab reappear

    /// Covers the mic-TCC-prompt case: the system-modal prompt never
    /// deactivates the app, so `didBecomeActiveNotification` doesn't fire
    /// and the wrapped service's `@Published statuses` stays stale.
    /// `viewModel.refresh()` must pull the latest snapshot regardless.
    func testRefreshReReadsLatestSnapshotFromService() {
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ])
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(viewModel.status(for: .microphone), .pending)

        // Stage a fresh snapshot WITHOUT firing `objectWillChange` —
        // simulates TCC state changing under the app's feet (e.g. mic
        // prompt accepted while the app stayed active).
        service.stageNextSnapshot([
            .microphone: .granted,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ])

        XCTAssertEqual(
            viewModel.status(for: .microphone),
            .pending,
            "view model should be stale until refresh() is called"
        )

        viewModel.refresh()

        XCTAssertEqual(viewModel.status(for: .microphone), .granted)
        XCTAssertEqual(viewModel.status(for: .inputMonitoring), .pending)
        XCTAssertEqual(viewModel.status(for: .accessibility), .pending)
    }

    func testRefreshCallsThroughToServiceRefresh() {
        let service = FakePermissionService()
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        viewModel.refresh()

        XCTAssertEqual(service.refreshCallCount, 1)
    }

    // MARK: - Status label selection (mockup-gaps C.4 / C.5)

    /// Non-granted permissions render an orange dot + the word
    /// **Required** beside a "Grant Access" pill button
    /// (`plans/App UI design/final_settings_permissions_v2.png`). The
    /// view reads the label string via `statusLabel(for:)` so the
    /// granted vs non-granted branch is a pure, testable helper.
    func testStatusLabelIsRequiredForPendingPermission() {
        let service = FakePermissionService(statuses: [
            .microphone: .pending,
        ])
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(
            viewModel.statusLabel(for: .microphone),
            "Required"
        )
    }

    func testStatusLabelIsRequiredForDeniedPermission() {
        let service = FakePermissionService(statuses: [
            .inputMonitoring: .denied,
        ])
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { _ in }
        )

        XCTAssertEqual(
            viewModel.statusLabel(for: .inputMonitoring),
            "Required"
        )
    }

    // MARK: - grantAccess URL routing

    func testGrantAccessOpensMicrophoneSystemSettingsURL() {
        let (viewModel, capturedURLs) = makeViewModelCapturingOpens()

        viewModel.grantAccess(for: .microphone)

        XCTAssertEqual(capturedURLs.values, [
            PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .microphone)
        ])
    }

    func testGrantAccessOpensInputMonitoringSystemSettingsURL() {
        let (viewModel, capturedURLs) = makeViewModelCapturingOpens()

        viewModel.grantAccess(for: .inputMonitoring)

        XCTAssertEqual(capturedURLs.values, [
            PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .inputMonitoring)
        ])
    }

    func testGrantAccessOpensAccessibilitySystemSettingsURL() {
        let (viewModel, capturedURLs) = makeViewModelCapturingOpens()

        viewModel.grantAccess(for: .accessibility)

        XCTAssertEqual(capturedURLs.values, [
            PermissionServiceAdapter.defaultSystemSettingsDeepLink(for: .accessibility)
        ])
    }

    // MARK: - Helpers

    private func makeViewModelCapturingOpens() -> (
        PermissionsSubTabViewModel,
        CapturedURLs
    ) {
        let captured = CapturedURLs()
        let service = FakePermissionService()
        let viewModel = PermissionsSubTabViewModel(
            permissionService: service,
            openURL: { url in
                captured.values.append(url)
            }
        )
        return (viewModel, captured)
    }

    private func drainMainQueue() {
        let expectation = expectation(description: "drain-main-queue")
        DispatchQueue.main.async {
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }
}

// MARK: - Test doubles

@MainActor
private final class CapturedURLs {
    var values: [URL] = []
}

@MainActor
private final class FakePermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]
    private(set) var refreshCallCount = 0
    private var nextSnapshot: [Permission: PermissionStatus]?

    init(
        statuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .inputMonitoring: .pending,
            .accessibility: .pending,
        ]
    ) {
        self.statuses = statuses
    }

    func updateStatuses(_ newStatuses: [Permission: PermissionStatus]) {
        statuses = newStatuses
    }

    /// Store a snapshot the next `refresh()` will pick up WITHOUT
    /// mutating `@Published statuses` — mirrors `AppKitPermissionService`,
    /// where `statusSnapshot()` re-queries TCC live while the stored
    /// `statuses` dict only updates when `refresh()` is called (or when
    /// `didBecomeActiveNotification` triggers it).
    func stageNextSnapshot(_ snapshot: [Permission: PermissionStatus]) {
        nextSnapshot = snapshot
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
        nextSnapshot ?? statuses
    }

    func refresh() {
        refreshCallCount += 1
        if let nextSnapshot {
            statuses = nextSnapshot
            self.nextSnapshot = nil
        }
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}
