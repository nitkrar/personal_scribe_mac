import XCTest
import SeshatCore
@testable import SeshatAudio

final class AVAudioCaptureServiceScaffoldingTests: XCTestCase {
    func testAVAudioCaptureServiceConformsToAudioCapturing() {
        let _: any AudioCapturing = AVAudioCaptureService()
    }
}
