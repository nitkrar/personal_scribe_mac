import XCTest
import SeshatCore
@testable import SeshatAppKit

@MainActor
final class AppKitMicrophonePermissionRequesterTests: XCTestCase {
    func testRequesterConformsToSharedProtocol() {
        let requester: any MicrophonePermissionRequesting = AppKitMicrophonePermissionRequester()
        XCTAssertNotNil(requester)
    }
}
