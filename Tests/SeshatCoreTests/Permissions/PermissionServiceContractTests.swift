import Foundation
import XCTest
@testable import SeshatCore

@MainActor
final class PermissionServiceContractTests: XCTestCase {
    func testPermissionServiceContractExposesLockedOperations() async {
        let service: any PermissionService = StubPermissionService()

        XCTAssertEqual(service.status(for: .microphone), .pending)
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
}

@MainActor
private final class StubPermissionService: PermissionService, @unchecked Sendable {
    func status(for permission: Permission) -> PermissionStatus {
        switch permission {
        case .microphone:
            return .pending
        case .inputMonitoring:
            return .granted
        case .accessibility:
            return .pending
        }
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
        Dictionary(
            uniqueKeysWithValues: Permission.allCases.map { permission in
                (permission, status(for: permission))
            }
        )
    }

    func refresh() {}

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
