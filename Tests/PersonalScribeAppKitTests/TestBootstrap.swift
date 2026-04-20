import AppKit
import XCTest

final class PersonalScribeCoreTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeCoreTestBootstrap = {
        let bootstrap = PersonalScribeCoreTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class PersonalScribeCoreTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeCoreTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(PersonalScribeCoreTestBootstrap.shared)
    }
}
