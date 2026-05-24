import XCTest
@testable import PersonalScribeCore

final class TranscriptionEngineCapabilitiesTests: XCTestCase {
    func testParakeetTDTHasASRCapability() {
        XCTAssertEqual(TranscriptionEngine.parakeetTDT.capabilities, [.asr])
    }

    func testParakeetEOUHasStreamingASRCapability() {
        XCTAssertEqual(TranscriptionEngine.parakeetEOU.capabilities, [.streamingASR])
    }

    func testQwen3ASRHasASRCapability() {
        XCTAssertEqual(TranscriptionEngine.qwen3ASR.capabilities, [.asr])
    }

    func testWhisperKitHasASRCapability() {
        XCTAssertEqual(TranscriptionEngine.whisperKit.capabilities, [.asr])
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
