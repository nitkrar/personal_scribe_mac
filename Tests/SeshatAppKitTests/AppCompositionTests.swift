import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class AppCompositionTests: XCTestCase {
    func testMakeSessionCoordinatorReturnsSharedIdleActor() async {
        let first = AppComposition.makeSessionCoordinator()
        let second = AppComposition.makeSessionCoordinator()

        XCTAssertTrue(first === second)
        let state = await first.state()
        XCTAssertEqual(state, .idle)
    }

    func testMakeMicrophonePermissionRequesterReturnsProductionType() async {
        let requester = AppComposition.makeMicrophonePermissionRequester()
        XCTAssertTrue(requester is AppKitMicrophonePermissionRequester)
    }
}
