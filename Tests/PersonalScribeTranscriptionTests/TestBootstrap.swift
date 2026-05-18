import AppKit
import XCTest

final class PersonalScribeAudioTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAudioTestBootstrap = {
        let bootstrap = PersonalScribeAudioTestBootstrap()
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            _ = NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

final class PersonalScribeAudioTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAudioTestBootstrap.shared
        super.setUp()
    }

    func testBootstrapRegistered() {
        XCTAssertNotNil(PersonalScribeAudioTestBootstrap.shared)
    }
}
