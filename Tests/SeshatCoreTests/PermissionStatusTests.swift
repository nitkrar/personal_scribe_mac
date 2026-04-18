import XCTest
@testable import SeshatCore

final class InputMonitoringPermissionStateTests: XCTestCase {
    func testStatesAreEquatable() {
        XCTAssertEqual(InputMonitoringPermissionState.granted, .granted)
        XCTAssertEqual(InputMonitoringPermissionState.denied, .denied)
        XCTAssertEqual(InputMonitoringPermissionState.notDetermined, .notDetermined)
        XCTAssertNotEqual(InputMonitoringPermissionState.granted, .denied)
    }

    func testPermissionProbingSupportsStubInjection() {
        struct StubbedProbe: PermissionProbing {
            let stubbed: InputMonitoringPermissionState
            func checkInputMonitoring() -> InputMonitoringPermissionState { stubbed }
        }

        XCTAssertEqual(StubbedProbe(stubbed: .granted).checkInputMonitoring(), .granted)
        XCTAssertEqual(StubbedProbe(stubbed: .denied).checkInputMonitoring(), .denied)
        XCTAssertEqual(StubbedProbe(stubbed: .notDetermined).checkInputMonitoring(), .notDetermined)
    }

    /// Smoke-level sanity: the real probe returns one of the three states
    /// (depends on the test host's TCC state — we can't assert a specific value).
    func testIOHIDProbeReturnsRecognisedState() {
        let probe = IOHIDPermissionProbe()
        let state = probe.checkInputMonitoring()

        switch state {
        case .granted, .denied, .notDetermined:
            break
        }
    }
}
