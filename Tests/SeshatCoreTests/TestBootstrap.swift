import AppKit
import XCTest

final class SeshatCoreTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: SeshatCoreTestBootstrap = {
        let bootstrap = SeshatCoreTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class SeshatCoreTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = SeshatCoreTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(SeshatCoreTestBootstrap.shared)
    }
}
