import XCTest
@testable import PersonalScribeCore

final class ModelKindIsEnabledTests: XCTestCase {
    func testAsrIsEnabled() {
        XCTAssertTrue(ModelKind.asr.isEnabled)
    }

    func testStreamingAsrIsEnabled() {
        XCTAssertTrue(ModelKind.streamingASR.isEnabled)
    }

    func testDiarizationIsEnabled() {
        XCTAssertTrue(ModelKind.diarization.isEnabled)
    }

    func testVadAndTtsRemainDisabled() {
        XCTAssertFalse(ModelKind.vad.isEnabled)
        XCTAssertFalse(ModelKind.tts.isEnabled)
    }
}
