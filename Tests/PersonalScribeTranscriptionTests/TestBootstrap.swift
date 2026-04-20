import AppKit
import XCTest

<<<<<<< Updated upstream
final class PersonalScribeAudioTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeAudioTestBootstrap = {
        let bootstrap = PersonalScribeAudioTestBootstrap()
=======
final class PersonalScribeTranscriptionTestBootstrap: NSObject, XCTestObservation, @unchecked Sendable {
    static let shared: PersonalScribeTranscriptionTestBootstrap = {
        let bootstrap = PersonalScribeTranscriptionTestBootstrap()
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
final class PersonalScribeAudioTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeAudioTestBootstrap.shared
=======
final class PersonalScribeTranscriptionTestBootstrapTrigger: XCTestCase {
    override class func setUp() {
        _ = PersonalScribeTranscriptionTestBootstrap.shared
>>>>>>> Stashed changes
        super.setUp()
    }

    func testBootstrapRegistered() {
<<<<<<< Updated upstream
        XCTAssertNotNil(PersonalScribeAudioTestBootstrap.shared)
=======
        XCTAssertNotNil(PersonalScribeTranscriptionTestBootstrap.shared)
>>>>>>> Stashed changes
    }
}
