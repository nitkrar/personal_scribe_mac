import Foundation
import os.signpost
import SeshatCore

public actor SessionCoordinator {
    private let capture: any AudioCapturing
    private let transcriber: any Transcribing
    private let transcriptStore: TranscriptStore?
    private let logger: SeshatLogger
    private let postProcessor = PostProcessor()
    private let signposter = OSSignposter(subsystem: SeshatLogger.subsystem, category: "prepare")

    private var currentState: SessionState = .idle
    private var mostRecentResult: TranscriptionResult?
    private var stateContinuations: [UUID: AsyncStream<SessionState>.Continuation] = [:]
    private var bufferedAudio: [PCMBuffer] = []
    private var captureTask: Task<Void, Never>?

    public init(
        capture: any AudioCapturing,
        transcriber: any Transcribing,
        logger: SeshatLogger,
        transcriptStore: TranscriptStore? = nil
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.transcriptStore = transcriptStore
        self.logger = logger
    }

    public func toggle() async {
        switch currentState {
        case .idle:
            await startRecording()
        case .recording:
            await stopRecordingAndTranscribe()
        case .transcribing:
            logger.info("Ignored toggle while transcribing")
        case .error:
            publish(.idle)
            await startRecording()
        }
    }

    public func state() -> SessionState {
        currentState
    }

    public func stateStream() -> AsyncStream<SessionState> {
        let id = UUID()

        return AsyncStream { continuation in
            continuation.yield(self.currentState)
            self.stateContinuations[id] = continuation
            continuation.onTermination = { [self] _ in
                Task {
                    await self.removeContinuation(id: id)
                }
            }
        }
    }

    public func lastResult() -> TranscriptionResult? {
        mostRecentResult
    }

    /// Idempotent passthrough for eager model preparation; `prepare()` coalesces repeated calls.
    public func prepareTranscriber() async throws {
        let intervalName: StaticString = "SessionCoordinator.prepareTranscriber"
        let state = signposter.beginInterval(intervalName)
        defer { signposter.endInterval(intervalName, state) }
        try await transcriber.prepare()
    }

    public func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        transcriber.modelDownloadProgress()
    }

    private func removeContinuation(id: UUID) {
        stateContinuations[id] = nil
    }

    private func publish(_ state: SessionState) {
        currentState = state
        for continuation in stateContinuations.values {
            continuation.yield(state)
        }
    }

    private func startRecording() async {
        bufferedAudio.removeAll(keepingCapacity: true)

        do {
            let stream = try await capture.start()
            publish(.recording)
            prepareTranscriberInBackground()
            captureTask = Task {
                await self.consumeCaptureStream(stream)
            }
        } catch {
            publish(.error(map(error, default: .audioEngineFailure)))
        }
    }

    private func stopRecordingAndTranscribe() async {
        await capture.stop()
        await captureTask?.value
        captureTask = nil

        if case .error = currentState {
            logger.info("Capture stream failed while stop was in flight; preserving error state")
            bufferedAudio.removeAll(keepingCapacity: true)
            return
        }

        let replayBuffers = bufferedAudio
        bufferedAudio.removeAll(keepingCapacity: true)
        publish(.transcribing)

        do {
            let raw = try await transcriber.transcribe(stream: makeReplayStream(from: replayBuffers))
            let cleanedText = postProcessor.clean(raw.text)
            mostRecentResult = TranscriptionResult(
                text: cleanedText,
                segments: raw.segments,
                audioDuration: raw.audioDuration,
                processingDuration: raw.processingDuration
            )
            await persistTranscript(
                text: cleanedText,
                audioDuration: raw.audioDuration,
                processingDuration: raw.processingDuration
            )
            publish(.idle)
        } catch {
            publish(.error(map(error, default: .transcriptionFailure)))
        }
    }

    private func persistTranscript(
        text: String,
        audioDuration: Duration,
        processingDuration: Duration
    ) async {
        guard let transcriptStore else {
            return
        }

        let entry = TranscriptEntry(
            id: UUID(),
            timestamp: Date(),
            text: text,
            audioDuration: Self.seconds(from: audioDuration),
            processingDuration: Self.seconds(from: processingDuration)
        )

        do {
            try await transcriptStore.append(entry)
        } catch {
            logger.error("Failed to persist transcript to TranscriptStore", error: error)
        }
    }

    private static func seconds(from duration: Duration) -> TimeInterval {
        let components = duration.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }

    private func consumeCaptureStream(_ stream: AsyncThrowingStream<PCMBuffer, Error>) async {
        do {
            for try await buffer in stream {
                bufferedAudio.append(buffer)
            }
        } catch {
            publish(.error(map(error, default: .audioEngineFailure)))
        }
    }

    private func makeReplayStream(from buffers: [PCMBuffer]) -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            for buffer in buffers {
                continuation.yield(buffer)
            }
            continuation.finish()
        }
    }

    private func map(_ error: any Error, default fallback: SeshatError) -> SeshatError {
        if let seshatError = error as? SeshatError {
            return seshatError
        }

        logger.error("Mapped underlying error to shared contract", error: error)
        return fallback
    }

    private func prepareTranscriberInBackground() {
        let transcriber = transcriber
        let logger = logger

        Task.detached(priority: .background) {
            do {
                try await transcriber.prepare()
            } catch is CancellationError {
                return
            } catch {
                logger.error("Background transcriber preparation failed", error: error)
            }
        }
    }
}
