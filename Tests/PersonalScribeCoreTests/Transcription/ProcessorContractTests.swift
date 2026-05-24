import XCTest
@testable import PersonalScribeCore

/// #078.21 — `Processor` is the role-erased processing surface that
/// returns a sum-typed `ProcessorOutput`. Tests pin the case set and
/// existential usability so the protocol cannot regress to an
/// associated-type shape.
final class ProcessorContractTests: XCTestCase {

    private actor ProbeProcessor: Processor {
        let pinnedOutput: ProcessorOutput
        private var prepared = false
        private var recordedPriors: [ProcessorOutput] = []

        init(pinnedOutput: ProcessorOutput) {
            self.pinnedOutput = pinnedOutput
        }

        func prepare() async throws {
            prepared = true
        }

        nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
            AsyncStream { continuation in
                continuation.finish()
            }
        }

        func releaseIdleResources() async {}

        func process(
            audio: PCMBuffer,
            priors: [ProcessorOutput]
        ) async throws -> ProcessorOutput {
            _ = audio
            recordedPriors = priors
            return pinnedOutput
        }

        func didPrepare() -> Bool {
            prepared
        }

        func priorCount() -> Int {
            recordedPriors.count
        }
    }

    private func makeBuffer() throws -> PCMBuffer {
        try PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        )
    }

    func testProcessorOutputCasesAreExhaustive() async throws {
        let textResult = TranscriptionResult(
            text: "batch",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(25)
        )
        let turn = SpeakerTurn(
            speakerID: "speaker_0",
            start: .zero,
            end: .seconds(1)
        )
        let outputs: [ProcessorOutput] = [
            .text(textResult),
            .streamingText(
                AsyncThrowingStream { continuation in
                    continuation.yield(.partial(text: "live"))
                    continuation.finish()
                }
            ),
            .turns(
                AsyncStream { continuation in
                    continuation.yield(.terminal([turn]))
                    continuation.finish()
                }
            ),
        ]

        var sawText = false
        var sawStreamingText = false
        var sawTurns = false

        for output in outputs {
            switch output {
            case .text(let result):
                sawText = true
                XCTAssertEqual(result, textResult)
            case .streamingText(let stream):
                sawStreamingText = true
                var iterator = stream.makeAsyncIterator()
                let first = try await iterator.next()
                XCTAssertEqual(first, .partial(text: "live"))
            case .turns(let stream):
                sawTurns = true
                var iterator = stream.makeAsyncIterator()
                let first = await iterator.next()
                XCTAssertEqual(first, .terminal([turn]))
            }
        }

        XCTAssertTrue(sawText)
        XCTAssertTrue(sawStreamingText)
        XCTAssertTrue(sawTurns)
    }

    func testProcessorExistentialComposesModelLifecycleAndAcceptsPriorOutputs() async throws {
        let pinnedResult = TranscriptionResult(
            text: "final",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(50)
        )
        let probe = ProbeProcessor(pinnedOutput: .text(pinnedResult))
        let processor: any Processor = probe
        let lifecycle: any ModelLifecycle = processor

        try await lifecycle.prepare()

        var progressEventCount = 0
        for await _ in lifecycle.modelDownloadProgress() {
            progressEventCount += 1
        }

        let priors: [ProcessorOutput] = [
            .text(
                TranscriptionResult(
                    text: "prior",
                    audioDuration: .milliseconds(500),
                    processingDuration: .milliseconds(10)
                )
            ),
        ]
        let output = try await processor.process(audio: try makeBuffer(), priors: priors)

        let didPrepare = await probe.didPrepare()
        XCTAssertTrue(didPrepare)
        XCTAssertEqual(progressEventCount, 0)
        let priorCount = await probe.priorCount()
        XCTAssertEqual(priorCount, 1)

        switch output {
        case .text(let result):
            XCTAssertEqual(result, pinnedResult)
        case .streamingText, .turns:
            XCTFail("Expected text output")
        }
    }
}
