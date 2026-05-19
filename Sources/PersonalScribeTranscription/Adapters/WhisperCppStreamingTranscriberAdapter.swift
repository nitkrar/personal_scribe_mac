@preconcurrency import whisper
import Foundation
import PersonalScribeCore

protocol WhisperCppStreamingManaging: Sendable {
    func loadModel(from modelFileURL: URL) async throws
    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment]
    func cleanup() async
}

protocol WhisperCppStreamingLibrary: Sendable {
    func createContext(modelPath: String) throws -> OpaquePointer
    func freeContext(_ context: OpaquePointer)
    func decodeSegments(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> [WhisperCppDecodedSegment]
}

public actor WhisperCppStreamingTranscriberAdapter: VadBoundaryStreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private static let decodeCadence: Duration = .milliseconds(500)
    private static let maxDecodeWindowSeconds: Double = 8.25
    private static let minimumDecodeWindowRms: Float = 0.001

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any WhisperCppStreamingManaging
    private let downloader: any WhisperCppDownloading
    private let vadBoundarySessionFactory: VadBoundarySessionFactory?
    private let logger: PersonalScribeLogger
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private let fileManager: FileManager
    private let idleUnloadDelay: Duration
    private let sleep: WhisperCppSleep
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?
    private var idleReleaseTask: Task<Void, Never>?
    private var idleReleaseGeneration: UInt64 = 0

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        vadBoundarySessionFactory: VadBoundarySessionFactory? = nil,
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription)
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperCppStreamingManager(),
            downloader: LiveWhisperCppDownloader(),
            vadBoundarySessionFactory: vadBoundarySessionFactory,
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any WhisperCppStreamingManaging,
        downloader: any WhisperCppDownloading,
        vadBoundarySessionFactory: VadBoundarySessionFactory? = nil,
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription),
        fileManager: FileManager = .default,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping WhisperCppSleep = { try await Task.sleep(for: $0) }
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.downloader = downloader
        self.vadBoundarySessionFactory = vadBoundarySessionFactory
        self.logger = logger
        self.fileManager = fileManager
        self.idleUnloadDelay = idleUnloadDelay
        self.sleep = sleep
    }

    public func prepare() async throws {
        invalidateIdleRelease()

        if hasPreparedModel {
            return
        }

        if let prepareTask {
            return try await prepareTask.value
        }

        let task = Task {
            try await self.performPrepare()
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
        } catch {
            prepareTask = nil
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public func downloadIfNeeded() async throws {
        do {
            try await performDownloadIfNeeded(emitFinished: true)
        } catch {
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func cleanup() async {
        invalidateIdleRelease()
        await cleanupRuntime()
    }

    public func releaseIdleResources() async {
        guard hasPreparedModel || prepareTask != nil else {
            return
        }

        invalidateIdleRelease()
        let generation = idleReleaseGeneration
        let delay = idleUnloadDelay
        let sleep = sleep
        idleReleaseTask = Task {
            do {
                try await sleep(delay)
            } catch {
                return
            }

            if Task.isCancelled {
                return
            }

            await self.finishIdleRelease(generation: generation)
        }
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        transcribe(
            stream: stream,
            eouSilenceThresholdSeconds: Double(
                PreferenceKeys.streamingEouSilenceThresholdMs.default
            ) / 1000
        )
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>,
        eouSilenceThresholdSeconds: Double
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.executeTranscription(
                    from: stream,
                    continuation: continuation,
                    eouSilenceThresholdSeconds: eouSilenceThresholdSeconds
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private extension WhisperCppStreamingTranscriberAdapter {
    var artifactStore: WhisperCppArtifactStore {
        WhisperCppArtifactStore(
            descriptor: descriptor,
            storageLocator: storageLocator,
            fileManager: fileManager
        )
    }

    func performPrepare() async throws {
        let modelFileURL = try artifactStore.modelFileURL()
        do {
            try Task.checkCancellation()
            try await performDownloadIfNeeded(emitFinished: false)
            try Task.checkCancellation()
            progressBroadcaster.emit(.loading)
            try await manager.loadModel(from: modelFileURL)
            try Task.checkCancellation()
            progressBroadcaster.emit(.finished)
        } catch is CancellationError {
            await manager.cleanup()
            throw CancellationError()
        } catch {
            await manager.cleanup()
            throw PersonalScribeError.modelLoadFailure
        }
    }

    func performDownloadIfNeeded(emitFinished: Bool) async throws {
        try await artifactStore.downloadIfNeeded(
            downloader: downloader,
            progressBroadcaster: progressBroadcaster,
            emitFinished: emitFinished
        )
    }

    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        eouSilenceThresholdSeconds: Double
    ) async {
        let startedAt = ContinuousClock.now

        do {
            try await prepare()
            let diagnosticsContext = StreamingDiagnosticsSession.current
                ?? StreamingDiagnosticsSession.Context()
            let vadSession = await vadBoundarySessionFactory?(eouSilenceThresholdSeconds)
            if vadSession == nil {
                logger.info(
                    "VAD boundary unavailable; falling back to stream-end boundary session=\(diagnosticsContext.sessionID) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds())"
                )
            }

            var tracker = WhisperCppStableSegmentTracker()
            var emittedUtteranceCount = 0
            var audioDuration: Duration = .zero
            var sinceLastDecode: Duration = .zero
            var firstBuffer: PCMBuffer?
            var sessionSamples: [Float] = []

            do {
                for try await buffer in stream {
                    try Task.checkCancellation()
                    try validateStreamShape(buffer, against: firstBuffer)
                    if firstBuffer == nil {
                        firstBuffer = buffer
                    }

                    audioDuration += buffer.duration
                    sinceLastDecode += buffer.duration
                    sessionSamples.append(contentsOf: buffer.samples)

                    if sinceLastDecode >= Self.decodeCadence {
                        try await decodeAndEmitPartialIfNeeded(
                            tracker: &tracker,
                            sessionSamples: sessionSamples,
                            sampleRate: buffer.sampleRate,
                            channelCount: buffer.channelCount,
                            continuation: continuation
                        )
                        sinceLastDecode = .zero
                    }

                    if let vadEvent = await vadSession?.ingest(buffer.samples),
                       vadEvent == .speechEnded
                    {
                        try await decodeAndEmitPartialIfNeeded(
                            tracker: &tracker,
                            sessionSamples: sessionSamples,
                            sampleRate: buffer.sampleRate,
                            channelCount: buffer.channelCount,
                            continuation: continuation
                        )
                        sinceLastDecode = .zero
                        emitBoundaryIfNeeded(
                            tracker: &tracker,
                            continuation: continuation,
                            diagnosticsContext: diagnosticsContext,
                            emittedUtteranceCount: &emittedUtteranceCount
                        )
                    }
                }
            } catch is CancellationError {
                continuation.finish()
                return
            } catch let error as PersonalScribeError {
                throw error
            } catch {
                throw PersonalScribeError.transcriptionFailure
            }

            if let firstBuffer {
                try await decodeAndEmitPartialIfNeeded(
                    tracker: &tracker,
                    sessionSamples: sessionSamples,
                    sampleRate: firstBuffer.sampleRate,
                    channelCount: firstBuffer.channelCount,
                    continuation: continuation
                )
            }

            emitBoundaryIfNeeded(
                tracker: &tracker,
                continuation: continuation,
                diagnosticsContext: diagnosticsContext,
                emittedUtteranceCount: &emittedUtteranceCount
            )

            continuation.yield(
                .finalized(
                    TranscriptionResult(
                        text: tracker.finalText,
                        audioDuration: audioDuration,
                        processingDuration: startedAt.duration(to: ContinuousClock.now)
                    )
                )
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch {
            continuation.finish(throwing: error)
        }
    }

    func decodeAndEmitPartialIfNeeded(
        tracker: inout WhisperCppStableSegmentTracker,
        sessionSamples: [Float],
        sampleRate: Double,
        channelCount: Int,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async throws {
        guard !sessionSamples.isEmpty else {
            return
        }

        let previousPartial = tracker.partialText
        let window = decodeWindow(
            from: sessionSamples,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        guard windowHasSpeechLikeEnergy(window.samples) else {
            return
        }

        do {
            let decoded = try await manager.decodeSegments(
                audioSamples: window.samples,
                languageHint: nil
            )
            let absoluteSegments = decoded.map { segment in
                WhisperCppDecodedSegment(
                    text: segment.text,
                    startMs: segment.startMs + window.windowStartMs,
                    endMs: segment.endMs + window.windowStartMs
                )
            }
            _ = tracker.ingest(absoluteSegments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }

        let partial = tracker.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty, partial != previousPartial else {
            return
        }
        continuation.yield(.partial(text: partial))
    }

    func emitBoundaryIfNeeded(
        tracker: inout WhisperCppStableSegmentTracker,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        diagnosticsContext: StreamingDiagnosticsSession.Context,
        emittedUtteranceCount: inout Int
    ) {
        guard
            let text = tracker.flushStablePrefix()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        emittedUtteranceCount += 1
        continuation.yield(.endOfUtterance(text: text))
        logger.info(
            "streaming_eou_emitted session=\(diagnosticsContext.sessionID) utterance=\(emittedUtteranceCount) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds()) chars=\(text.count)"
        )
    }

    func decodeWindow(
        from sessionSamples: [Float],
        sampleRate: Double,
        channelCount: Int
    ) -> (samples: [Float], windowStartMs: Int64) {
        let maxWindowFrames = Int(Self.maxDecodeWindowSeconds * sampleRate)
        let maxWindowSamples = maxWindowFrames * channelCount

        guard sessionSamples.count > maxWindowSamples else {
            return (sessionSamples, 0)
        }

        let windowSamples = Array(sessionSamples.suffix(maxWindowSamples))
        let droppedFrames = (sessionSamples.count - windowSamples.count) / channelCount
        let windowStartMs = Int64((Double(droppedFrames) / sampleRate) * 1_000)
        return (windowSamples, windowStartMs)
    }

    func windowHasSpeechLikeEnergy(_ samples: [Float]) -> Bool {
        guard !samples.isEmpty else {
            return false
        }

        let meanSquare = samples.reduce(into: Float.zero) { partialResult, sample in
            partialResult += sample * sample
        } / Float(samples.count)
        return sqrt(meanSquare) >= Self.minimumDecodeWindowRms
    }

    func validateStreamShape(_ buffer: PCMBuffer, against firstBuffer: PCMBuffer?) throws {
        guard let firstBuffer else {
            return
        }

        guard
            buffer.sampleRate == firstBuffer.sampleRate,
            buffer.channelCount == firstBuffer.channelCount
        else {
            throw PersonalScribeError.transcriptionFailure
        }
    }

    func invalidateIdleRelease() {
        idleReleaseGeneration &+= 1
        idleReleaseTask?.cancel()
        idleReleaseTask = nil
    }

    func finishIdleRelease(generation: UInt64) async {
        guard generation == idleReleaseGeneration else {
            return
        }

        idleReleaseTask = nil
        await cleanupRuntime()
    }

    func cleanupRuntime() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }
}

internal final class LiveWhisperCppStreamingManager: WhisperCppStreamingManaging, @unchecked Sendable {
    private enum RuntimeError: Error {
        case modelNotLoaded
    }

    private let queue = DispatchQueue(label: "personal_scribe.whispercpp.streaming.runtime")
    private let library: any WhisperCppStreamingLibrary
    private var context: OpaquePointer?
    private var loadedModelPath: String?

    init(library: any WhisperCppStreamingLibrary = LiveWhisperCppStreamingLibrary()) {
        self.library = library
    }

    func loadModel(from modelFileURL: URL) async throws {
        let standardizedPath = modelFileURL.standardizedFileURL.path
        try await enqueue {
            if self.context != nil, self.loadedModelPath == standardizedPath {
                return
            }

            if let context = self.context {
                self.library.freeContext(context)
                self.context = nil
                self.loadedModelPath = nil
            }

            let context = try self.library.createContext(modelPath: standardizedPath)
            self.context = context
            self.loadedModelPath = standardizedPath
        }
    }

    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment] {
        let nThreads = Self.defaultThreadCount()
        return try await enqueue {
            guard let context = self.context else {
                throw RuntimeError.modelNotLoaded
            }

            return try self.library.decodeSegments(
                context: context,
                audioSamples: audioSamples,
                nThreads: nThreads,
                languageHint: languageHint
            )
        }
    }

    func cleanup() async {
        try? await enqueue {
            if let context = self.context {
                self.library.freeContext(context)
            }
            self.context = nil
            self.loadedModelPath = nil
        }
    }

    private func enqueue<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultThreadCount() -> Int32 {
        let availableProcessors = ProcessInfo.processInfo.activeProcessorCount
        return Int32(max(1, min(8, availableProcessors - 2)))
    }
}

private struct LiveWhisperCppStreamingLibrary: WhisperCppStreamingLibrary {
    private enum LibraryError: Error {
        case contextInitFailed
        case transcriptionFailed
    }

    func createContext(modelPath: String) throws -> OpaquePointer {
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw LibraryError.contextInitFailed
        }

        return context
    }

    func freeContext(_ context: OpaquePointer) {
        whisper_free(context)
    }

    func decodeSegments(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> [WhisperCppDecodedSegment] {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        params.suppress_blank = true
        params.suppress_nst = true
        params.n_threads = nThreads
        params.offset_ms = 0
        params.duration_ms = 0

        let resolvedLanguage = languageHint ?? "auto"
        let resultCode = resolvedLanguage.withCString { languageCString -> Int32 in
            params.language = languageCString
            whisper_reset_timings(context)
            return audioSamples.withUnsafeBufferPointer { samples in
                whisper_full(context, params, samples.baseAddress, Int32(samples.count))
            }
        }

        guard resultCode == 0 else {
            throw LibraryError.transcriptionFailed
        }

        var segments: [WhisperCppDecodedSegment] = []
        let segmentCount = Int(whisper_full_n_segments(context))
        segments.reserveCapacity(segmentCount)

        for index in 0..<segmentCount {
            guard let segmentText = whisper_full_get_segment_text(context, Int32(index)) else {
                continue
            }

            let text = String(cString: segmentText).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                continue
            }

            // whisper.cpp segment timestamps are reported in 10 ms
            // ticks, so convert them to milliseconds before the
            // adapter rebases them onto the session timeline.
            let startMs = whisper_full_get_segment_t0(context, Int32(index)) * 10
            let endMs = whisper_full_get_segment_t1(context, Int32(index)) * 10
            segments.append(
                WhisperCppDecodedSegment(
                    text: text,
                    startMs: startMs,
                    endMs: endMs
                )
            )
        }

        return segments
    }
}
