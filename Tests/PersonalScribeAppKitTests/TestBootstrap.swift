import AppKit
import XCTest

<<<<<<< Updated upstream
final class PersonalScribeCoreTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeCoreTestBootstrap = {
        let bootstrap = PersonalScribeCoreTestBootstrap()
=======
final class PersonalScribeAppKitTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAppKitTestBootstrap = {
        let bootstrap = PersonalScribeAppKitTestBootstrap()
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
final class PersonalScribeCoreTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeCoreTestBootstrap.shared
=======
final class PersonalScribeAppKitTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAppKitTestBootstrap.shared
>>>>>>> Stashed changes
        super.setUp()
    }

    func testBootstrapRegistered() {
<<<<<<< Updated upstream
        XCTAssertNotNil(PersonalScribeCoreTestBootstrap.shared)
=======
        XCTAssertNotNil(PersonalScribeAppKitTestBootstrap.shared)
>>>>>>> Stashed changes
    }
}
