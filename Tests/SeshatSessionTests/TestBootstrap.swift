import AppKit
import XCTest

final class SeshatSessionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: SeshatSessionTestBootstrap = {
        let bootstrap = SeshatSessionTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class SeshatSessionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = SeshatSessionTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(SeshatSessionTestBootstrap.shared)
    }
}
