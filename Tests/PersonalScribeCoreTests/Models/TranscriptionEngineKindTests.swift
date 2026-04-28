import XCTest
@testable import PersonalScribeCore

/// #078.7 — `TranscriptionEngine.kind` is the computed-from-engine
/// view of `ModelKind` per L2. The four hardcoded mapping tests are
/// the load-bearing oracle for "engine→kind dispatch is correct."
/// The catalog-convention test is a consistency check between the
/// stored `kind` field on every catalog descriptor and the
/// engine-derived value (the stored field is removed at Phase H.6
/// — the consistency check loses its bite then; the four hardcoded
/// tests retain it).
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

    func testDiarizationMapsToDiarization() {
        XCTAssertEqual(TranscriptionEngine.diarization.kind, .diarization)
    }

}
