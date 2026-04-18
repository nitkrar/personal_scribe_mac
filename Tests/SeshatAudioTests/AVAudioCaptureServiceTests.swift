import XCTest
import SeshatCore
@testable import SeshatAudio

final class AuthorizationTests: XCTestCase {
    func testStartThrowsMicPermissionDeniedWhenStatusIsDenied() async throws {
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .denied },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }

    func testStartThrowsMicPermissionDeniedWhenStatusIsNotDetermined() async throws {
        let service = AVAudioCaptureService(
            authorizationStatusProvider: { .notDetermined },
            engineDriver: .testStub(),
            resamplerFactory: { rate, logger in
                try AudioResampler(inputSampleRate: rate, logger: logger)
            }
        )

        do {
            _ = try await service.start()
            XCTFail("Expected micPermissionDenied")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .micPermissionDenied)
        }
    }
}
