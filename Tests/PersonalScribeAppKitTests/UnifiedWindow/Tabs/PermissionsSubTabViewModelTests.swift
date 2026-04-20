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

    func refresh() {}

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        URL(string: "https://example.invalid/\(permission.rawValue)")!
    }
}
