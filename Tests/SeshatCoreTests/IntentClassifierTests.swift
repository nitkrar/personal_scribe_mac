import XCTest
@testable import SeshatCore

final class IntentClassifierTests: XCTestCase {
    func testNoOpClassifierAlwaysReturnsDictationForEmptyString() async {
        let classifier: any IntentClassifier = NoOpIntentClassifier()

        let intent = await classifier.classify("")

        XCTAssertEqual(intent, .dictation)
    }

    func testNoOpClassifierAlwaysReturnsDictationForArbitraryText() async {
        let classifier: any IntentClassifier = NoOpIntentClassifier()

        let dictationLike = await classifier.classify("hello world, let me write this down")
        let commandLike = await classifier.classify("open settings")
        let queryLike = await classifier.classify("what time is it")

        XCTAssertEqual(dictationLike, .dictation)
        XCTAssertEqual(commandLike, .dictation)
        XCTAssertEqual(queryLike, .dictation)
    }

    func testIntentEnumExposesAllFourCases() {
        // Guardrail: Phase 4 will depend on these four cases existing. If a
        // future edit removes or renames any, the Phase 4 plug point breaks.
        let all: [Intent] = [.dictation, .command, .query, .unknown]
        XCTAssertEqual(Set(all).count, 4)
    }

    func testNoOpClassifierIsSendable() {
        // Compile-time check: the no-op classifier must cross actor boundaries
        // without warnings under Swift 6 strict concurrency.
        let classifier = NoOpIntentClassifier()
        Task.detached {
            _ = await classifier.classify("cross-actor call")
        }
    }
}
