import XCTest
@testable import PersonalScribeAppKit

final class SingleInstanceGuardTests: XCTestCase {
    func testOtherInstanceIgnoresCurrentAndTerminatedProcesses() {
        let running = [
            SingleInstanceGuard.Instance(pid: 100, isTerminated: false),
            SingleInstanceGuard.Instance(pid: 200, isTerminated: true),
        ]

        XCTAssertNil(SingleInstanceGuard.otherInstance(in: running, currentPID: 100))
    }

    func testOtherInstanceFindsAnotherLiveCopy() {
        let running = [
            SingleInstanceGuard.Instance(pid: 100, isTerminated: false),
            SingleInstanceGuard.Instance(pid: 300, isTerminated: false),
        ]

        XCTAssertEqual(SingleInstanceGuard.otherInstance(in: running, currentPID: 100)?.pid, 300)
    }
}
