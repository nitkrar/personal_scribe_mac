import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class AppEntryPointTests: XCTestCase {
    func testSeshatAppMainBuildsSceneModelFromComposition() async {
        let entry = SeshatAppMain()

        XCTAssertTrue(entry.coordinator === AppComposition.sessionCoordinator)
        XCTAssertEqual(await entry.coordinator.state(), .idle)
    }
}
