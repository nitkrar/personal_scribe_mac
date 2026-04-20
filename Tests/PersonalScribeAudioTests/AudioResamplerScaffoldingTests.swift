import XCTest
@testable import PersonalScribeAudio

final class AudioResamplerScaffoldingTests: XCTestCase {
    func testAudioResamplerSymbolCompiles() async throws {
        _ = try AudioResampler(inputSampleRate: 44_100)
    }
}
