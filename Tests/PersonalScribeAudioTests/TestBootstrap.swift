import AppKit
import XCTest

<<<<<<< Updated upstream
final class PersonalScribeAppKitTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAppKitTestBootstrap = {
        let bootstrap = PersonalScribeAppKitTestBootstrap()
=======
final class PersonalScribeAudioTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAudioTestBootstrap = {
        let bootstrap = PersonalScribeAudioTestBootstrap()
>>>>>>> Stashed changes
        XCTestObservationCenter.shared.addTestObserver(bootstrap)
        return bootstrap
    }()

    func testBundleWillStart(_ testBundle: Bundle) {
        MainActor.assumeIsolated {
            NSApplication.shared.setActivationPolicy(.accessory)
        }
    }
}

<<<<<<< Updated upstream
final class PersonalScribeAppKitTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAppKitTestBootstrap.shared
=======
final class PersonalScribeAudioTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAudioTestBootstrap.shared
>>>>>>> Stashed changes
        super.setUp()
    }

    func testBootstrapRegistered() {
<<<<<<< Updated upstream
        XCTAssertNotNil(PersonalScribeAppKitTestBootstrap.shared)
=======
        XCTAssertNotNil(PersonalScribeAudioTestBootstrap.shared)
>>>>>>> Stashed changes
    }
}
