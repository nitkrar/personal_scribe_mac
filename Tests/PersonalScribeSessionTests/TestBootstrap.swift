import AppKit
import XCTest

<<<<<<< Updated upstream
final class PersonalScribeSessionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeSessionTestBootstrap = {
        let bootstrap = PersonalScribeSessionTestBootstrap()
=======
final class PersonalScribeSessionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeSessionTestBootstrap = {
        let bootstrap = PersonalScribeSessionTestBootstrap()
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
final class PersonalScribeSessionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeSessionTestBootstrap.shared
=======
final class PersonalScribeSessionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeSessionTestBootstrap.shared
>>>>>>> Stashed changes
        super.setUp()
    }

    func testBootstrapRegistered() {
<<<<<<< Updated upstream
        XCTAssertNotNil(PersonalScribeSessionTestBootstrap.shared)
=======
        XCTAssertNotNil(PersonalScribeSessionTestBootstrap.shared)
>>>>>>> Stashed changes
    }
}
