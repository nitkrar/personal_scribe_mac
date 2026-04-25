import Foundation
import PersonalScribeCore
import PersonalScribeSession
import PersonalScribeTestSupport

@MainActor
enum DevelopmentComposition {
    static func makeTestingSessionCoordinator(
        buffers: [PCMBuffer] = defaultBuffers(),
        result: TranscriptionResult = defaultResult(),
        captureError: PersonalScribeError? = nil,
        transcribeError: PersonalScribeError? = nil,
        logger: PersonalScribeLogger = PersonalScribeLogger(category: PersonalScribeLogCategory.ui)
    ) -> SessionCoordinator {
        SessionCoordinator(
            capture: FakeAudioCapturer(
                buffers: buffers,
                error: captureError
            ),
            transcriber: FakeTranscriber(
                result: result,
                transcribeError: transcribeError
            ),
            logger: logger
        )
    }

    private static func defaultResult() -> TranscriptionResult {
        TranscriptionResult(
            text: "development transcript",
            audioDuration: .seconds(1),
            processingDuration: .milliseconds(100)
        )
    }

    // One second of silence — enough to clear SessionPipelineOrchestrator's
    // `.shortExit` guard (>= 1s of buffered audio).
    private static func defaultBuffers() -> [PCMBuffer] {
        guard let buffer = try? PCMBuffer(
            samples: Array(repeating: 0, count: 16_000),
            timestamp: ContinuousClock().now
        ) else {
            return []
        }
        return [buffer]
    }
}
