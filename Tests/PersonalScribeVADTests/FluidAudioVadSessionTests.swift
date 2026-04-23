import FluidAudio
import XCTest

@testable import PersonalScribeVAD

final class FluidAudioVadSessionTests: XCTestCase {

    func testAccumulatesOddSizedBuffersIntoChunkSizedInference() async {
        // Capture contract: upstream PCM buffers are variable size (AVAudioEngine
        // tap, resampler output). The session must accumulate into exactly
        // VadManager.chunkSize (4096) samples before invoking inference — Silero
        // is not tolerant of under/over-sized windows in streaming mode.
        let counter = InferenceCallCounter()
        let session = FluidAudioVadSession(
            inference: { chunk, _, _ in
                XCTAssertEqual(
                    chunk.count, VadManager.chunkSize,
                    "inference must always receive exactly chunkSize samples"
                )
                await counter.increment()
                return VadStreamResult(state: .initial(), event: nil, probability: 0.1)
            },
            config: .default
        )

        _ = await session.ingest(Array(repeating: Float(0), count: 500))
        var calls = await counter.count
        XCTAssertEqual(calls, 0, "500 samples < chunkSize: no inference yet")

        _ = await session.ingest(Array(repeating: Float(0), count: 4000))
        calls = await counter.count
        XCTAssertEqual(calls, 1, "500+4000=4500 samples: one 4096 chunk consumed, 404 pending")

        _ = await session.ingest(Array(repeating: Float(0), count: 3692))
        calls = await counter.count
        XCTAssertEqual(calls, 2, "404+3692=4096 samples exactly: one more chunk")
    }
}

// MARK: - Test fakes

private actor InferenceCallCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}
