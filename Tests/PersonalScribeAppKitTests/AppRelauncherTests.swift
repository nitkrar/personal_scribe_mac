import XCTest
@testable import PersonalScribeAppKit

final class AppRelauncherTests: XCTestCase {
    func testRelaunchHelperOpensAppOnlyAfterOriginalProcessExits() throws {
        let original = Process()
        original.executableURL = URL(fileURLWithPath: "/bin/sleep")
        original.arguments = ["0.5"]
        try original.run()

        let marker = FileManager.default.temporaryDirectory
            .appendingPathComponent("relaunch-marker-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: marker) }

        let helper = try AppRelauncher.spawnRelaunchHelper(
            waitingFor: original.processIdentifier,
            appURL: marker,
            opener: "/usr/bin/touch"
        )

        Thread.sleep(forTimeInterval: 0.25)
        XCTAssertTrue(original.isRunning)
        XCTAssertFalse(FileManager.default.fileExists(atPath: marker.path))

        helper.waitUntilExit()
        XCTAssertFalse(original.isRunning)
        XCTAssertTrue(FileManager.default.fileExists(atPath: marker.path))
    }
}
