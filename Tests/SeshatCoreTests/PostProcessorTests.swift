import XCTest
@testable import SeshatCore

final class PostProcessorTests: XCTestCase {
    private let postProcessor = PostProcessor()

    func testEmptyInputReturnsEmpty() {
        XCTAssertEqual(postProcessor.clean(""), "")
        XCTAssertEqual(postProcessor.clean("   \n  "), "")
    }

    func testRemovesCommonFillers() {
        XCTAssertEqual(postProcessor.clean("um hello uh world"), "Hello world.")
    }

    func testRemovesHedges() {
        XCTAssertEqual(postProcessor.clean("you know i think sort of it works"), "I think it works.")
    }

    func testPreservesTerminalPunctuation() {
        XCTAssertEqual(postProcessor.clean("hello!"), "Hello!")
    }

    func testAddsMissingPeriod() {
        XCTAssertEqual(postProcessor.clean("hello"), "Hello.")
    }

    func testCollapsesInternalWhitespace() {
        XCTAssertEqual(postProcessor.clean("hello    world"), "Hello world.")
    }

    func testIsDeterministic() {
        let input = "um hello uh world"

        XCTAssertEqual(postProcessor.clean(input), postProcessor.clean(input))
    }

    func testDoesNotCorruptProperNouns() {
        XCTAssertEqual(postProcessor.clean("my name is Matthew"), "My name is Matthew.")
    }
}
