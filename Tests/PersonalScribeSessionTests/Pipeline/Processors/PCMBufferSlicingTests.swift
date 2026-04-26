import XCTest
@testable import PersonalScribeCore
@testable import PersonalScribeSession

final class PCMBufferSlicingTests: XCTestCase {
    func testSliceReturnsSampleAccurateRange() throws {
        let buffer = try makeMonoBuffer(samples: (0..<10).map(Float.init), sampleRate: 10)

        let slice = try PCMBufferSlicing.slice(
            buffer,
            from: .milliseconds(200),
            to: .milliseconds(500),
            sampleRate: 10
        )

        XCTAssertEqual(slice.samples, [2, 3, 4])
        XCTAssertEqual(slice.frameCount, 3)
        XCTAssertEqual(slice.channelCount, 1)
        XCTAssertEqual(slice.sampleRate, 10)
    }

    func testSliceClampsToBufferBounds() throws {
        let buffer = try makeMonoBuffer(samples: (0..<10).map(Float.init), sampleRate: 10)

        let slice = try PCMBufferSlicing.slice(
            buffer,
            from: .milliseconds(-200),
            to: .milliseconds(1_400),
            sampleRate: 10
        )

        XCTAssertEqual(slice.samples, buffer.samples)
        XCTAssertEqual(slice.frameCount, buffer.frameCount)
    }

    func testSliceOfZeroDurationReturnsEmptyBuffer() throws {
        let buffer = try makeMonoBuffer(samples: (0..<10).map(Float.init), sampleRate: 10)

        let slice = try PCMBufferSlicing.slice(
            buffer,
            from: .milliseconds(400),
            to: .milliseconds(400),
            sampleRate: 10
        )

        XCTAssertTrue(slice.samples.isEmpty)
        XCTAssertEqual(slice.frameCount, 0)
        XCTAssertEqual(slice.duration, .zero)
        XCTAssertEqual(slice.channelCount, buffer.channelCount)
    }

    func testSliceWithStereoBufferPreservesChannels() throws {
        let buffer = try makeStereoBuffer(
            frames: [(1, 10), (2, 20), (3, 30), (4, 40)],
            sampleRate: 4
        )

        let slice = try PCMBufferSlicing.slice(
            buffer,
            from: .milliseconds(250),
            to: .milliseconds(750),
            sampleRate: 4
        )

        XCTAssertEqual(slice.channelCount, 2)
        XCTAssertEqual(slice.frameCount, 2)
        XCTAssertEqual(slice.samples, [2, 20, 3, 30])
    }

    func testSliceWithFractionalSampleStartUsesNearestSampleBoundary() throws {
        let buffer = try makeMonoBuffer(samples: (0..<10).map(Float.init), sampleRate: 10)

        let slice = try PCMBufferSlicing.slice(
            buffer,
            from: .milliseconds(251),
            to: .milliseconds(449),
            sampleRate: 10
        )

        XCTAssertEqual(slice.samples, [2, 3, 4])
    }

    func testSliceWithSampleRateMismatchThrowsOrConverts() throws {
        let buffer = try makeMonoBuffer(samples: (0..<10).map(Float.init), sampleRate: 10)

        XCTAssertThrowsError(
            try PCMBufferSlicing.slice(
                buffer,
                from: .zero,
                to: .milliseconds(500),
                sampleRate: 8
            )
        ) { error in
            XCTAssertEqual(error as? PersonalScribeError, .resampleFailure)
        }
    }
}

private extension PCMBufferSlicingTests {
    func makeMonoBuffer(
        samples: [Float],
        sampleRate: Double
    ) throws -> PCMBuffer {
        try PCMBuffer(
            samples: samples,
            sampleRate: sampleRate,
            channelCount: 1,
            timestamp: ContinuousClock().now
        )
    }

    func makeStereoBuffer(
        frames: [(Float, Float)],
        sampleRate: Double
    ) throws -> PCMBuffer {
        try PCMBuffer(
            samples: frames.flatMap { [$0.0, $0.1] },
            sampleRate: sampleRate,
            channelCount: 2,
            timestamp: ContinuousClock().now
        )
    }
}
