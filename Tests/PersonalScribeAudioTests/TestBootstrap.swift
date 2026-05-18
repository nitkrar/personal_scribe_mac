import AppKit
import XCTest

final class PersonalScribeAppKitTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAppKitTestBootstrap = {
        let bootstrap = PersonalScribeAppKitTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class PersonalScribeAppKitTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAppKitTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(PersonalScribeAppKitTestBootstrap.shared)
    }
}
