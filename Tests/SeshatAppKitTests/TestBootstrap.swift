import AppKit
import XCTest

final class SeshatAppKitTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: SeshatAppKitTestBootstrap = {
        let bootstrap = SeshatAppKitTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class SeshatAppKitTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = SeshatAppKitTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(SeshatAppKitTestBootstrap.shared)
    }
}
