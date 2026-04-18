import XCTest
import SeshatCore
import SeshatSession
@testable import SeshatAppKit

@MainActor
final class MenuBarFlowIntegrationTests: XCTestCase {
    func testDevelopmentCompositionCreatesIdleTestingCoordinator() async {
        let coordinator = DevelopmentComposition.makeTestingSessionCoordinator()

        let state = await coordinator.state()
        XCTAssertEqual(state, .idle)
    }
}
