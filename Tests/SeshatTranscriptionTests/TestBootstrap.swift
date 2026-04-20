import AppKit
import XCTest

final class SeshatTranscriptionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: SeshatTranscriptionTestBootstrap = {
        let bootstrap = SeshatTranscriptionTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class SeshatTranscriptionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = SeshatTranscriptionTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(SeshatTranscriptionTestBootstrap.shared)
    }
}
