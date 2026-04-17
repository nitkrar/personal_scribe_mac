import XCTest
@testable import SeshatAudio

final class AudioResamplerScaffoldingTests: XCTestCase {
    func testAudioResamplerSymbolCompiles() async throws {
        _ = try AudioResampler(inputSampleRate: 44_100)
    }
}
