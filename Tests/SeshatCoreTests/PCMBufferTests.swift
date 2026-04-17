import XCTest
@testable import SeshatCore

final class PCMBufferTests: XCTestCase {
    func testDurationAndValidation() throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )

        XCTAssertEqual(buffer.frameCount, 16_000)
        XCTAssertEqual(buffer.duration, .seconds(1))

        XCTAssertThrowsError(
            try PCMBuffer(
                samples: [0],
                sampleRate: 0,
                timestamp: ContinuousClock().now
            )
        ) { error in
            XCTAssertEqual(error as? SeshatError, .resampleFailure)
        }

        XCTAssertThrowsError(
            try PCMBuffer(
                samples: [0],
                sampleRate: 16_000,
                channelCount: 2,
                timestamp: ContinuousClock().now
            )
        ) { error in
            XCTAssertEqual(error as? SeshatError, .resampleFailure)
        }
    }
}
