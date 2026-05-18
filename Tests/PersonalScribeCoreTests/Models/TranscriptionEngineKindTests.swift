import XCTest
@testable import PersonalScribeCore

/// #078.7 — `TranscriptionEngine.kind` is the computed-from-engine
/// view of `ModelKind` per L2. These hardcoded mapping tests are the
/// load-bearing oracle for "engine→kind dispatch is correct."
final class TranscriptionEngineKindTests: XCTestCase {

    func testParakeetTDTMapsToAsr() {
        XCTAssertEqual(TranscriptionEngine.parakeetTDT.kind, .asr)
    }

    func testParakeetEOUMapsToStreamingASR() {
        XCTAssertEqual(TranscriptionEngine.parakeetEOU.kind, .streamingASR)
    }

    func testQwen3ASRMapsToAsr() {
        XCTAssertEqual(TranscriptionEngine.qwen3ASR.kind, .asr)
    }

    func testWhisperKitMapsToAsr() {
        XCTAssertEqual(TranscriptionEngine.whisperKit.kind, .asr)
    }

    func testWhisperCppMapsToAsr() {
        XCTAssertEqual(TranscriptionEngine.whisperCpp.kind, .asr)
    }

    func testDiarizationMapsToDiarization() {
        XCTAssertEqual(TranscriptionEngine.diarization.kind, .diarization)
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
