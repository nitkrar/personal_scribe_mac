import XCTest
import PersonalScribeCore
@testable import PersonalScribeAudio

final class AVAudioCaptureServiceScaffoldingTests: XCTestCase {
    func testAVAudioCaptureServiceConformsToAudioCapturing() {
        let _: any AudioCapturing = AVAudioCaptureService()
    }
}
