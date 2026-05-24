@preconcurrency import WhisperKit
import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeTranscription

final class WhisperKitStreamingLedgerTests: XCTestCase {
    func testConsumeEmitsPartialForUnconfirmedSegments() {
        var ledger = WhisperKitStreamingLedger()

        let events = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [],
                unconfirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                    makeSegment(start: 0.5, end: 1.0, text: "world"),
                ]
            )
        )

        XCTAssertEqual(events, [.partial(text: "hello world")])
    }

    func testConsumeEmitsEndOfUtteranceWhenNewConfirmedSegmentsAppear() {
        var ledger = WhisperKitStreamingLedger()
        _ = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [],
                unconfirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                    makeSegment(start: 0.5, end: 1.0, text: "world"),
                ]
            )
        )

        let events = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                ],
                unconfirmedSegments: [
                    makeSegment(start: 0.5, end: 1.0, text: "world"),
                    makeSegment(start: 1.0, end: 1.5, text: "again"),
                ]
            )
        )

        XCTAssertEqual(events, [.endOfUtterance(text: "hello")])
    }

    func testConsumeAdvancesWatermarkSoNextCallDoesNotReEmit() {
        var ledger = WhisperKitStreamingLedger()
        _ = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                ],
                unconfirmedSegments: []
            )
        )

        let events = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                ],
                unconfirmedSegments: []
            )
        )

        XCTAssertEqual(events, [])
    }

    func testJoinedTextStripsSpecialTokensFromSegments() {
        let text = WhisperKitStreamingLedger.joinedText(
            [
                makeSegment(
                    start: 0,
                    end: 1,
                    text: "<|startoftranscript|><|en|><|transcribe|><|0.00|> hello<|1.00|>"
                ),
            ]
        )

        XCTAssertEqual(text, "hello")
    }

    func testPartialEventEmittedAfterStrippingHasNoSpecialTokens() {
        var ledger = WhisperKitStreamingLedger()

        let events = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [],
                unconfirmedSegments: [
                    makeSegment(
                        start: 0,
                        end: 1,
                        text: "<|startoftranscript|><|en|><|transcribe|><|0.00|> hello<|1.00|>"
                    ),
                ]
            )
        )

        XCTAssertEqual(events, [.partial(text: "hello")])
    }

    func testEndOfUtteranceTextHasNoSpecialTokens() {
        var ledger = WhisperKitStreamingLedger()

        let events = ledger.consume(
            WhisperKitStreamingState(
                confirmedSegments: [
                    makeSegment(
                        start: 0,
                        end: 1,
                        text: "<|startoftranscript|><|en|><|transcribe|><|0.00|> hello<|1.00|>"
                    ),
                ],
                unconfirmedSegments: []
            )
        )

        XCTAssertEqual(events, [.endOfUtterance(text: "hello")])
    }

    func testOverlappingSegmentsAreMergedIntoOneTimedText() {
        let text = WhisperKitStreamingLedger.joinedText(
            [
                makeSegment(start: 0, end: 2, text: "hello world"),
                makeSegment(start: 1.5, end: 3, text: "world again"),
            ]
        )

        XCTAssertEqual(text, "hello world again")
    }

    func testFinalTextFallsBackToFallbackStateWhenLedgerEmpty() {
        let ledger = WhisperKitStreamingLedger()

        let text = ledger.finalText(
            fallbackState: WhisperKitStreamingState(
                confirmedSegments: [
                    makeSegment(start: 0, end: 0.5, text: "hello"),
                ],
                unconfirmedSegments: [
                    makeSegment(start: 0.5, end: 1.0, text: "world"),
                ]
            )
        )

        XCTAssertEqual(text, "hello world")
    }
}

private extension WhisperKitStreamingLedgerTests {
    func makeSegment(
        start: Float,
        end: Float,
        text: String
    ) -> TranscriptionSegment {
        TranscriptionSegment(
            start: start,
            end: end,
            text: text
        )
    }
}
