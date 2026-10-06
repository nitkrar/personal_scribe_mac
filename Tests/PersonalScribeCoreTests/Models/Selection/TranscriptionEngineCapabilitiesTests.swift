import XCTest
@testable import PersonalScribeCore

final class TranscriptionEngineCapabilitiesTests: XCTestCase {
    func testParakeetTDTHasASRCapability() {
        XCTAssertEqual(TranscriptionEngine.parakeetTDT.capabilities, [.asr])
    }

    func testParakeetEOUHasStreamingASRCapability() {
        XCTAssertEqual(TranscriptionEngine.parakeetEOU.capabilities, [.streamingASR])
    }

    func testWhisperKitHasBatchAndStreamingCapabilities() {
        XCTAssertEqual(TranscriptionEngine.whisperKit.capabilities, [.asr, .streamingASR])
    }

    func testWhisperCppHasBatchAndStreamingCapabilities() {
        XCTAssertEqual(TranscriptionEngine.whisperCpp.capabilities, [.asr, .streamingASR])
    }

    func testDiarizationHasDiarizationCapability() {
        XCTAssertEqual(TranscriptionEngine.diarization.capabilities, [.diarization])
    }

    func testWhisperCppCodableRoundTrips() throws {
        let data = try JSONEncoder().encode(TranscriptionEngine.whisperCpp)

        XCTAssertEqual(String(data: data, encoding: .utf8), "\"whisperCpp\"")
        XCTAssertEqual(
            try JSONDecoder().decode(TranscriptionEngine.self, from: data),
            .whisperCpp
        )
    }
}
