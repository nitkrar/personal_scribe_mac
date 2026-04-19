import AVFoundation
import Combine
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class AppKitPermissionServiceTests: XCTestCase {
    func testInitialRefreshSeedsPublishedStatusSnapshot() {
        let fixture = Fixture()
        fixture.microphone.authorizationStatus = .authorized
        fixture.inputMonitoring.status = .denied
        fixture.accessibility.isTrusted = false

        let service = fixture.makeService()

        XCTAssertEqual(
            service.statuses,
            [
                .microphone: .granted,
                .inputMonitoring: .denied,
                .accessibility: .pending,
            ]
        )
        XCTAssertEqual(fixture.activationObserver.registrationCount, 1)
    }

    func testStatusReadsCurrentOSStateWithoutRequiringRefresh() {
        let fixture = Fixture()
        let service = fixture.makeService()

        fixture.microphone.authorizationStatus = .denied
        fixture.inputMonitoring.status = .granted
        fixture.accessibility.isTrusted = true

        XCTAssertEqual(service.status(for: .microphone), .denied)
        XCTAssertEqual(service.status(for: .inputMonitoring), .granted)
        XCTAssertEqual(service.status(for: .accessibility), .granted)
    }

    func testAccessibilityUntrustedMapsToPendingNotDenied() {
        let fixture = Fixture()
        fixture.accessibility.isTrusted = false

        let service = fixture.makeService()

        XCTAssertEqual(service.status(for: .accessibility), .pending)
        XCTAssertNotEqual(service.status(for: .accessibility), .denied)
    }

    func testSystemSettingsDeepLinksMatchPermissionKind() {
        let fixture = Fixture()
        let service = fixture.makeService()

        XCTAssertEqual(
            service.systemSettingsDeepLink(for: .microphone).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        )
        XCTAssertEqual(
            service.systemSettingsDeepLink(for: .inputMonitoring).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"
        )
        XCTAssertEqual(
            service.systemSettingsDeepLink(for: .accessibility).absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        )
    }

    func testRequestMicrophonePromptsOnlyWhenPending() async {
        let fixture = Fixture()
        fixture.microphone.authorizationStatus = .notDetermined
        fixture.microphone.requestResult = false
        fixture.microphone.authorizationStatusAfterRequest = .denied
        let service = fixture.makeService()

        let outcome = await service.request(.microphone)

        XCTAssertEqual(fixture.microphone.requestAccessCallCount, 1)
        XCTAssertTrue(outcome.prompted)
        XCTAssertFalse(outcome.openedSettings)
        XCTAssertFalse(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .denied)
        XCTAssertTrue(fixture.urlOpener.openedURLs.isEmpty)
        XCTAssertEqual(service.statuses[.microphone], .denied)
    }

    func testRequestMicrophoneOpensSettingsWhenDenied() async {
        let fixture = Fixture()
        fixture.microphone.authorizationStatus = .restricted
        let service = fixture.makeService()

        let outcome = await service.request(.microphone)

        XCTAssertEqual(fixture.microphone.requestAccessCallCount, 0)
        XCTAssertFalse(outcome.prompted)
        XCTAssertTrue(outcome.openedSettings)
        XCTAssertFalse(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .denied)
        XCTAssertEqual(
            fixture.urlOpener.openedURLs,
            [service.systemSettingsDeepLink(for: .microphone)]
        )
    }

    func testRequestInputMonitoringRequiresRelaunchWhenPromptPathRuns() async {
        let fixture = Fixture()
        fixture.inputMonitoring.status = .pending
        fixture.inputMonitoring.requestAccessResult = false
        fixture.inputMonitoring.statusAfterRequest = .denied
        let service = fixture.makeService()

        let outcome = await service.request(.inputMonitoring)

        XCTAssertEqual(fixture.inputMonitoring.requestAccessCallCount, 1)
        XCTAssertTrue(outcome.prompted)
        XCTAssertFalse(outcome.openedSettings)
        XCTAssertTrue(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .denied)
        XCTAssertTrue(fixture.urlOpener.openedURLs.isEmpty)
    }

    func testRequestInputMonitoringRequiresRelaunchWhenSettingsPathRuns() async {
        let fixture = Fixture()
        fixture.inputMonitoring.status = .denied
        let service = fixture.makeService()

        let outcome = await service.request(.inputMonitoring)

        XCTAssertEqual(fixture.inputMonitoring.requestAccessCallCount, 0)
        XCTAssertFalse(outcome.prompted)
        XCTAssertTrue(outcome.openedSettings)
        XCTAssertTrue(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .denied)
        XCTAssertEqual(
            fixture.urlOpener.openedURLs,
            [service.systemSettingsDeepLink(for: .inputMonitoring)]
        )
    }

    func testRequestAccessibilityTriggersPromptWithoutFakingDenied() async {
        let fixture = Fixture()
        fixture.accessibility.isTrusted = false
        fixture.accessibility.requestResult = false
        fixture.accessibility.isTrustedAfterRequest = false
        let service = fixture.makeService()

        let outcome = await service.request(.accessibility)

        XCTAssertEqual(fixture.accessibility.requestAccessCallCount, 1)
        XCTAssertTrue(outcome.prompted)
        XCTAssertFalse(outcome.openedSettings)
        XCTAssertFalse(outcome.requiresRelaunch)
        XCTAssertEqual(outcome.finalStatus, .pending)
        XCTAssertTrue(fixture.urlOpener.openedURLs.isEmpty)
        XCTAssertEqual(service.statuses[.accessibility], .pending)
    }

    func testRefreshPublishesSingleSnapshotUpdate() {
        let fixture = Fixture()
        let service = fixture.makeService()
        var snapshots: [[Permission: PermissionStatus]] = []
        var cancellable: AnyCancellable?

        cancellable = service.$statuses
            .dropFirst()
            .sink { snapshots.append($0) }

        fixture.microphone.authorizationStatus = .authorized
        fixture.inputMonitoring.status = .granted
        fixture.accessibility.isTrusted = true

        service.refresh()
        _ = cancellable

        XCTAssertEqual(snapshots.count, 1)
        XCTAssertEqual(
            snapshots.first,
            [
                .microphone: .granted,
                .inputMonitoring: .granted,
                .accessibility: .granted,
            ]
        )
    }

    func testDidBecomeActiveNotificationTriggersRefresh() {
        let fixture = Fixture()
        let service = fixture.makeService()

        fixture.microphone.authorizationStatus = .authorized
        fixture.inputMonitoring.status = .granted
        fixture.accessibility.isTrusted = true

        fixture.activationObserver.triggerDidBecomeActive()

        XCTAssertEqual(
            service.statuses,
            [
                .microphone: .granted,
                .inputMonitoring: .granted,
                .accessibility: .granted,
            ]
        )
    }

    func testDeinitCancelsActivationObservation() {
        let fixture = Fixture()
        var service: AppKitPermissionService? = fixture.makeService()

        XCTAssertEqual(fixture.activationObserver.cancellationCount, 0)

        service = nil

        XCTAssertNil(service)
        XCTAssertEqual(fixture.activationObserver.cancellationCount, 1)
    }
}

@MainActor
private struct Fixture {
    let microphone = MicrophonePermissionSpy()
    let inputMonitoring = InputMonitoringPermissionSpy()
    let accessibility = AccessibilityPermissionSpy()
    let urlOpener = URLOpenerSpy()
    let activationObserver = ActivationObserverSpy()

    func makeService() -> AppKitPermissionService {
        AppKitPermissionService(
            microphone: microphone.client,
            inputMonitoring: inputMonitoring.client,
            accessibility: accessibility.client,
            urlOpener: urlOpener.opener,
            activationObserver: activationObserver.observer
        )
    }
}

@MainActor
private final class MicrophonePermissionSpy {
    var authorizationStatus: AVAuthorizationStatus = .notDetermined
    var authorizationStatusAfterRequest: AVAuthorizationStatus?
    var requestResult = false
    private(set) var authorizationStatusCallCount = 0
    private(set) var requestAccessCallCount = 0

    var client: MicrophonePermissionClient {
        MicrophonePermissionClient(
            authorizationStatus: { [unowned self] in
                authorizationStatusCallCount += 1
                return authorizationStatus
            },
            requestAccess: { [unowned self] in
                requestAccessCallCount += 1
                if let authorizationStatusAfterRequest {
                    authorizationStatus = authorizationStatusAfterRequest
                }
                return requestResult
            }
        )
    }
}

@MainActor
private final class InputMonitoringPermissionSpy {
    var status: PermissionStatus = .pending
    var statusAfterRequest: PermissionStatus?
    var requestAccessResult = false
    private(set) var statusCallCount = 0
    private(set) var requestAccessCallCount = 0

    var client: InputMonitoringPermissionClient {
        InputMonitoringPermissionClient(
            status: { [unowned self] in
                statusCallCount += 1
                return status
            },
            requestAccess: { [unowned self] in
                requestAccessCallCount += 1
                if let statusAfterRequest {
                    status = statusAfterRequest
                }
                return requestAccessResult
            }
        )
    }
}

@MainActor
private final class AccessibilityPermissionSpy {
    var isTrusted = false
    var isTrustedAfterRequest: Bool?
    var requestResult = false
    private(set) var isTrustedCallCount = 0
    private(set) var requestAccessCallCount = 0

    var client: AccessibilityPermissionClient {
        AccessibilityPermissionClient(
            isTrusted: { [unowned self] in
                isTrustedCallCount += 1
                return isTrusted
            },
            requestAccess: { [unowned self] in
                requestAccessCallCount += 1
                if let isTrustedAfterRequest {
                    isTrusted = isTrustedAfterRequest
                }
                return requestResult
            }
        )
    }
}

@MainActor
private final class URLOpenerSpy {
    private(set) var openedURLs: [URL] = []

    var opener: PermissionURLOpener {
        PermissionURLOpener(open: { [unowned self] url in
            openedURLs.append(url)
        })
    }
}

@MainActor
private final class ActivationObserverSpy {
    private(set) var registrationCount = 0
    private(set) var cancellationCount = 0
    private var handler: (@MainActor () -> Void)?

    var observer: ApplicationActivationObserver {
        ApplicationActivationObserver(observe: { [unowned self] handler in
            registrationCount += 1
            self.handler = handler
            return ActivationObservation(cancel: { [weak self] in
                self?.cancellationCount += 1
            })
        })
    }

    func triggerDidBecomeActive() {
        handler?()
    }
}
