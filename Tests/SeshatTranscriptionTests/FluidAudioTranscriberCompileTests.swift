import XCTest
import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberCompileTests: XCTestCase {
    func testFluidAudioTranscriberConformsToTranscribing() {
        let transcriber: any Transcribing = FluidAudioTranscriber(
            logger: SeshatLogger(category: SeshatLogCategory.transcription)
        )

        XCTAssertNotNil(transcriber)
    }
}
