import AppKit
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class NotesWindowControllerTests: XCTestCase {
    func testShowWindowOpensControllerWindowOnceAndReusesIt() {
        _ = NSApplication.shared
        let controller = NotesWindowController(
            transcriptReader: NotesStubTranscriptReader(allEntries: [])
        )

        controller.showWindow(nil)
        let firstWindow = controller.window

        controller.showWindow(nil)
        let secondWindow = controller.window

        XCTAssertNotNil(firstWindow)
        XCTAssertTrue(firstWindow === secondWindow)

        controller.close()
    }

    func testHostReusesSingleControllerInstance() {
        _ = NSApplication.shared
        var factoryCallCount = 0
        let host = NotesWindowControllerHost(
            controllerFactory: {
                factoryCallCount += 1
                return NotesWindowController(
                    transcriptReader: NotesStubTranscriptReader(allEntries: [])
                )
            }
        )

        host.showWindow(nil)
        host.showWindow(nil)

        XCTAssertEqual(factoryCallCount, 1)
    }
}
