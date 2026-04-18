import Foundation
import SeshatCore
import SeshatSession
import SeshatTestSupport

@MainActor
enum DevelopmentComposition {
    static func makeTestingSessionCoordinator(
        buffers: [PCMBuffer] = [],
        result: TranscriptionResult = defaultResult(),
        captureError: SeshatError? = nil,
        transcribeError: SeshatError? = nil,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.ui)
    ) -> SessionCoordinator {
        SessionCoordinator(
            capture: FakeAudioCapturing(
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
}
