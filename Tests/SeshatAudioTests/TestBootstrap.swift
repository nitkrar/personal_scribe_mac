import AppKit
import XCTest

final class SeshatAudioTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: SeshatAudioTestBootstrap = {
        let bootstrap = SeshatAudioTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class SeshatAudioTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = SeshatAudioTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(SeshatAudioTestBootstrap.shared)
    }
}
