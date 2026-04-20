import Combine
import Foundation
import XCTest
@testable import PersonalScribeCore

@MainActor
final class PermissionServiceContractTests: XCTestCase {
    func testPermissionServiceContractExposesLockedOperations() async {
        let stub = StubPermissionService()
        let service: any PermissionService = stub

        XCTAssertEqual(service.status(for: .microphone), .pending)
        XCTAssertEqual(
            service.statuses,
            [
                .microphone: .pending,
                .inputMonitoring: .granted,
                .accessibility: .pending,
            ]
        )
        XCTAssertEqual(
            service.statusSnapshot(),
            [
                .microphone: .pending,
                .inputMonitoring: .granted,
                .accessibility: .pending,
            ]
        )

        let requestOutcome = await service.request(.inputMonitoring)
        XCTAssertEqual(
            requestOutcome,
            RequestOutcome(
                prompted: true,
                openedSettings: false,
                requiresRelaunch: true,
                finalStatus: .granted
            )
        )

        service.refresh()

        XCTAssertEqual(
            service.systemSettingsDeepLink(for: .accessibility).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testPermissionServiceObservableContractPublishesStatusesThroughExistential() {
        let stub = StubPermissionService()
        let service: any PermissionService = stub
        let expectedStatuses: [Permission: PermissionStatus] = [
            .microphone: .granted,
            .inputMonitoring: .granted,
            .accessibility: .granted,
        ]
        var changeCount = 0
        let cancellable = observeObjectWillChange(for: service) {
            changeCount += 1
        }

        stub.refreshedStatuses = expectedStatuses

        service.refresh()
        _ = cancellable

        XCTAssertEqual(changeCount, 1)
        XCTAssertEqual(service.statuses, expectedStatuses)
    }
}

@MainActor
private final class StubPermissionService: PermissionService {
    @Published private(set) var statuses: [Permission: PermissionStatus]

    var refreshedStatuses: [Permission: PermissionStatus]

    init() {
        let initialStatuses: [Permission: PermissionStatus] = [
            .microphone: .pending,
            .inputMonitoring: .granted,
            .accessibility: .pending,
        ]
        self.statuses = initialStatuses
        self.refreshedStatuses = initialStatuses
    }

    func status(for permission: Permission) -> PermissionStatus {
        statuses[permission] ?? .pending
    }

    func request(_ permission: Permission) async -> RequestOutcome {
        return RequestOutcome(
            prompted: permission == .inputMonitoring,
            openedSettings: false,
            requiresRelaunch: permission == .inputMonitoring,
            finalStatus: status(for: permission)
        )
    }

    func statusSnapshot() -> [Permission: PermissionStatus] {
        statuses
    }

    func refresh() {
        statuses = refreshedStatuses
    }

    func systemSettingsDeepLink(for permission: Permission) -> URL {
        switch permission {
        case .microphone:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
            )!
        case .inputMonitoring:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
            )!
        case .accessibility:
            return URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            )!
        }
    }
}

@MainActor
private func observeObjectWillChange<Service: PermissionService>(
    for service: Service,
    onChange: @escaping @MainActor () -> Void
) -> AnyCancellable {
    service.objectWillChange.sink { _ in
        MainActor.assumeIsolated {
            onChange()
        }
    }
}
