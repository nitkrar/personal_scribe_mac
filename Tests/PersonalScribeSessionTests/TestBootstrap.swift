import AppKit
import XCTest

final class PersonalScribeSessionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeSessionTestBootstrap = {
        let bootstrap = PersonalScribeSessionTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class PersonalScribeSessionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeSessionTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(PersonalScribeSessionTestBootstrap.shared)
    }
}
