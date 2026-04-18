import AVFoundation
import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class AppKitMicrophonePermissionRequesterTests: XCTestCase {
    func testRequesterConformsToSharedProtocol() {
        let requester: any MicrophonePermissionRequesting = AppKitMicrophonePermissionRequester()
        XCTAssertNotNil(requester)
    }

    func testCurrentStateMapsNotDeterminedToNotYetRequested() {
        let requester = AppKitMicrophonePermissionRequester(
            statusProvider: { .notDetermined },
            accessRequester: { true }
        )

        XCTAssertEqual(requester.currentState(), .notYetRequested)
    }

    func testCurrentStateMapsAuthorizedToGranted() {
        let requester = AppKitMicrophonePermissionRequester(
            statusProvider: { .authorized },
            accessRequester: { false }
        )

        XCTAssertEqual(requester.currentState(), .granted)
    }

    func testCurrentStateMapsDeniedToDenied() {
        let requester = AppKitMicrophonePermissionRequester(
            statusProvider: { .denied },
            accessRequester: { true }
        )

        XCTAssertEqual(requester.currentState(), .denied)
    }

    func testRequestAccessCachesGrantedDecision() async {
        var accessRequestCount = 0
        let requester = AppKitMicrophonePermissionRequester(
            statusProvider: { .authorized },
            accessRequester: {
                accessRequestCount += 1
                return true
            }
        )

        let granted = await requester.requestAccess()

        XCTAssertTrue(granted)
        XCTAssertEqual(accessRequestCount, 0)
    }

    func testRequestAccessCachesDeniedDecision() async {
        var accessRequestCount = 0
        let requester = AppKitMicrophonePermissionRequester(
            statusProvider: { .restricted },
            accessRequester: {
                accessRequestCount += 1
                return true
            }
        )

        let granted = await requester.requestAccess()

        XCTAssertFalse(granted)
        XCTAssertEqual(accessRequestCount, 0)
    }
}
