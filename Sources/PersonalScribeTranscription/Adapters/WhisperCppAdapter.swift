@preconcurrency import whisper
import Foundation
import PersonalScribeCore
import PersonalScribeVAD

typealias WhisperCppSleep = @Sendable (Duration) async throws -> Void

protocol WhisperCppManaging: Sendable {
    func loadModel(from modelFileURL: URL) async throws
    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> WhisperCppManagerResult
    func decodeSegments(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperCppDecodedSegment]
    func cleanup() async
}

protocol WhisperCppDownloading: Sendable {
    func download(
        from remoteURL: URL,
        to temporaryURL: URL,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}

protocol WhisperCppLibrary: Sendable {
    func createContext(modelPath: String) throws -> OpaquePointer
    func freeContext(_ context: OpaquePointer)
    func transcribe(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> String
    func decodeSegments(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> [WhisperCppDecodedSegment]
}

struct WhisperCppManagerResult: Sendable, Equatable {
    let text: String
}

package enum WhisperCppStreamingVadEvent: Sendable, Equatable {
    case speechEnded
    case speechResumed
}

package struct WhisperCppStreamingVadSessionHandle: Sendable {
    package let ingest: @Sendable ([Float]) async -> WhisperCppStreamingVadEvent?

    package init(
        ingest: @escaping @Sendable ([Float]) async -> WhisperCppStreamingVadEvent?
    ) {
        self.ingest = ingest
    }
}

package typealias WhisperCppStreamingVadSessionFactory =
    @Sendable (_ silenceThresholdSeconds: Double) async -> WhisperCppStreamingVadSessionHandle?

public actor WhisperCppAdapter: Transcriber, StreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    static let decodeCadence: Duration = .milliseconds(500)
    static let maxDecodeWindowSeconds: Double = 8.25
    static let minimumDecodeWindowRms: Float = 0.005

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any WhisperCppManaging
    private let downloader: any WhisperCppDownloading
    private let vadSessionFactory: WhisperCppStreamingVadSessionFactory?
    private let eouSilenceThresholdMsResolver: @Sendable () -> Int
    private let logger: PersonalScribeLogger?
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
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperCppManager(),
            downloader: LiveWhisperCppDownloader(),
            vadSessionFactory: Self.liveVadSessionFactory(logger: nil),
            eouSilenceThresholdMsResolver: {
                PreferenceKeys.streamingEouSilenceThresholdMs.default
            },
            logger: nil,
            idleUnloadDelay: .seconds(30)
        )
    }

    package init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperCppManager(),
            downloader: LiveWhisperCppDownloader(),
            vadSessionFactory: Self.liveVadSessionFactory(logger: logger),
            eouSilenceThresholdMsResolver: {
                PreferenceKeys.streamingEouSilenceThresholdMs.default
            },
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    package init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger,
        vadSessionFactory: WhisperCppStreamingVadSessionFactory?,
        eouSilenceThresholdMsResolver: @escaping @Sendable () -> Int = {
            PreferenceKeys.streamingEouSilenceThresholdMs.default
        }
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperCppManager(),
            downloader: LiveWhisperCppDownloader(),
            vadSessionFactory: vadSessionFactory,
            eouSilenceThresholdMsResolver: eouSilenceThresholdMsResolver,
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any WhisperCppManaging,
        downloader: any WhisperCppDownloading,
        vadSessionFactory: WhisperCppStreamingVadSessionFactory? = nil,
        eouSilenceThresholdMsResolver: @escaping @Sendable () -> Int = {
            PreferenceKeys.streamingEouSilenceThresholdMs.default
        },
        logger: PersonalScribeLogger? = nil,
        fileManager: FileManager = .default,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping WhisperCppSleep = { try await Task.sleep(for: $0) }
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.downloader = downloader
        self.vadSessionFactory = vadSessionFactory
        self.eouSilenceThresholdMsResolver = eouSilenceThresholdMsResolver
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

    public func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let result = try await manager.transcribe(
                audioSamples: audio.samples,
                languageHint: languageHint
            )
            let measuredTotalDuration = startedAt.duration(to: ContinuousClock.now)
            return makeTranscriptionResult(
                from: result,
                audioDuration: audio.duration,
                processingDuration: measuredTotalDuration
            )
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }
    }

    public nonisolated func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                await self.executeTranscription(
                    from: stream,
                    continuation: continuation
                )
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}

private extension WhisperCppAdapter {
    enum DecodeAttempt {
        case skipped
        case succeeded
        case failed
    }

    struct StreamingEventSummary {
        var partialCount = 0
        var eouCount = 0
    }

    static func liveVadSessionFactory(
        logger: PersonalScribeLogger?
    ) -> WhisperCppStreamingVadSessionFactory? {
        guard let vadProvider = try? FluidAudioVadProvider(logger: logger) else {
            return nil
        }

        return { silenceThresholdSeconds in
            guard let session = await vadProvider.makeSession(
                silenceThresholdSeconds: silenceThresholdSeconds
            ) else {
                return nil
            }

            return WhisperCppStreamingVadSessionHandle { samples in
                switch await session.ingest(samples) {
                case .speechEnded:
                    return .speechEnded
                case .speechResumed:
                    return .speechResumed
                case nil:
                    return nil
                }
            }
        }
    }

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

    func makeTranscriptionResult(
        from result: WhisperCppManagerResult,
        audioDuration: Duration,
        processingDuration: Duration
    ) -> TranscriptionResult {
        TranscriptionResult(
            text: result.text,
            audioDuration: audioDuration,
            processingDuration: processingDuration
        )
    }

    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async {
        let startedAt = ContinuousClock.now
        var bufferCount = 0
        var audioDuration: Duration = .zero
        var summary = StreamingEventSummary()
        var outcome = "prepare_failed"
        var finalTextEmpty = true

        defer {
            logger?.info(
                "streaming_adapter_summary — descriptorID=\(descriptor.id) bufferCount=\(bufferCount) partialCount=\(summary.partialCount) eouCount=\(summary.eouCount) outcome=\(outcome) finalTextEmpty=\(finalTextEmpty) audioDurationMs=\(Self.milliseconds(from: audioDuration))"
            )
        }

        do {
            try await prepare()
            outcome = "completed"

            let silenceThresholdSeconds =
                Double(eouSilenceThresholdMsResolver()) / 1000
            let vadSession = await vadSessionFactory?(silenceThresholdSeconds)
            if vadSession == nil {
                logger?.info(
                    "VAD boundary unavailable; falling back to stream-end boundary descriptorID=\(descriptor.id)"
                )
            }

            var tracker = WhisperCppStableSegmentTracker()
            var emittedUtteranceCount = 0
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

                    bufferCount += 1
                    audioDuration = audioDuration + buffer.duration
                    sinceLastDecode = sinceLastDecode + buffer.duration
                    sessionSamples.append(contentsOf: buffer.samples)

                    let vadEvent = await vadSession?.ingest(buffer.samples)
                    let shouldDecode =
                        sinceLastDecode >= Self.decodeCadence
                        || vadEvent == .speechEnded

                    if shouldDecode {
                        let attempt = try await decodeAndEmitPartialIfNeeded(
                            tracker: &tracker,
                            sessionSamples: sessionSamples,
                            sampleRate: buffer.sampleRate,
                            channelCount: buffer.channelCount,
                            continuation: continuation,
                            summary: &summary
                        )
                        if attempt == .failed {
                            outcome = "decode_failed"
                            let finalText = tracker.finalText.trimmingCharacters(
                                in: .whitespacesAndNewlines
                            )
                            finalTextEmpty = finalText.isEmpty
                            finalize(
                                text: finalText,
                                audioDuration: audioDuration,
                                processingDuration: startedAt.duration(to: ContinuousClock.now),
                                continuation: continuation
                            )
                            return
                        }
                        sinceLastDecode = .zero
                    }

                    if vadEvent == .speechEnded {
                        emitBoundaryIfNeeded(
                            tracker: &tracker,
                            continuation: continuation,
                            emittedUtteranceCount: &emittedUtteranceCount,
                            summary: &summary
                        )
                    }
                }
            } catch is CancellationError {
                outcome = "cancelled"
                continuation.finish()
                return
            } catch let error as PersonalScribeError {
                outcome = "stream_failed"
                throw error
            } catch {
                outcome = "stream_failed"
                throw PersonalScribeError.transcriptionFailure
            }

            if let firstBuffer {
                try Task.checkCancellation()
                let attempt = try await decodeAndEmitPartialIfNeeded(
                    tracker: &tracker,
                    sessionSamples: sessionSamples,
                    sampleRate: firstBuffer.sampleRate,
                    channelCount: firstBuffer.channelCount,
                    continuation: continuation,
                    summary: &summary
                )
                if attempt == .failed {
                    outcome = "decode_failed"
                    let finalText = tracker.finalText.trimmingCharacters(
                        in: .whitespacesAndNewlines
                    )
                    finalTextEmpty = finalText.isEmpty
                    finalize(
                        text: finalText,
                        audioDuration: audioDuration,
                        processingDuration: startedAt.duration(to: ContinuousClock.now),
                        continuation: continuation
                    )
                    return
                }
            }

            emitBoundaryIfNeeded(
                tracker: &tracker,
                continuation: continuation,
                emittedUtteranceCount: &emittedUtteranceCount,
                summary: &summary
            )

            let finalText = tracker.finalText.trimmingCharacters(in: .whitespacesAndNewlines)
            finalTextEmpty = finalText.isEmpty
            finalize(
                text: finalText,
                audioDuration: audioDuration,
                processingDuration: startedAt.duration(to: ContinuousClock.now),
                continuation: continuation
            )
        } catch is CancellationError {
            outcome = "cancelled"
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
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        summary: inout StreamingEventSummary
    ) async throws -> DecodeAttempt {
        guard !sessionSamples.isEmpty else {
            return .skipped
        }

        let window = decodeWindow(
            from: sessionSamples,
            sampleRate: sampleRate,
            channelCount: channelCount
        )
        guard windowHasSpeechLikeEnergy(window.samples) else {
            return .skipped
        }

        let previousPartial = tracker.partialText

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
            return .failed
        }

        let partial = tracker.partialText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !partial.isEmpty, partial != previousPartial else {
            return .succeeded
        }

        summary.partialCount += 1
        continuation.yield(.partial(text: partial))
        return .succeeded
    }

    func emitBoundaryIfNeeded(
        tracker: inout WhisperCppStableSegmentTracker,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        emittedUtteranceCount: inout Int,
        summary: inout StreamingEventSummary
    ) {
        guard
            let text = tracker.flushStablePrefix()?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            return
        }

        emittedUtteranceCount += 1
        summary.eouCount += 1
        continuation.yield(.endOfUtterance(text: text))
        logger?.info(
            "streaming_eou_emitted descriptorID=\(descriptor.id) utterance=\(emittedUtteranceCount) chars=\(text.count)"
        )
    }

    func finalize(
        text: String,
        audioDuration: Duration,
        processingDuration: Duration,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) {
        continuation.yield(
            .finalized(
                TranscriptionResult(
                    text: text,
                    audioDuration: audioDuration,
                    processingDuration: processingDuration
                )
            )
        )
        continuation.finish()
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

        let meanSquare = samples.reduce(into: Float.zero) { partial, sample in
            partial += sample * sample
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
        let hadPrepared = hasPreparedModel
        let hadInFlightPrepare = prepareTask != nil
        guard hadPrepared || hadInFlightPrepare else {
            return
        }

        await cleanupRuntime()
        logger?.info(
            "adapter_idle_release — descriptorID=\(descriptor.id) adapter=\(String(describing: type(of: self))) releasedAfterMs=\(Self.milliseconds(from: idleUnloadDelay)) hadPrepared=\(hadPrepared) hadInFlightPrepare=\(hadInFlightPrepare)"
        )
    }

    func cleanupRuntime() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }

    static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
        return Int((seconds * 1000).rounded())
    }
}

internal final class LiveWhisperCppDownloader: WhisperCppDownloading, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func download(
        from remoteURL: URL,
        to temporaryURL: URL,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try fileManager.createDirectory(
            at: temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw URLError(.cannotCreateFile)
        }

        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        let delegate = WhisperCppStreamingDownloadDelegate(
            fileHandle: fileHandle,
            progressHandler: progressHandler
        )
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer {
            session.finishTasksAndInvalidate()
        }

        do {
            try await delegate.download(with: session, from: remoteURL)
        } catch {
            try? fileHandle.close()
            throw error
        }
    }
}

private final class WhisperCppStreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let progressHandler: @Sendable (ModelDownloadProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasCompleted = false
    private var bytesReceived: Int64 = 0
    private var expectedBytes: Int64?

    init(
        fileHandle: FileHandle,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) {
        self.fileHandle = fileHandle
        self.progressHandler = progressHandler
    }

    func download(with session: URLSession, from remoteURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }

            let task = session.dataTask(with: remoteURL)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            complete(with: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }

        let responseLength = response.expectedContentLength
        expectedBytes = responseLength > 0 ? responseLength : nil
        progressHandler(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0,
            receivedBytes: 0,
            expectedBytes: expectedBytes
        ))
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !isCompleted else {
            return
        }

        do {
            try fileHandle.write(contentsOf: data)
            bytesReceived += Int64(data.count)
            let fractionCompleted: Double
            if let expectedBytes, expectedBytes > 0 {
                fractionCompleted = min(max(Double(bytesReceived) / Double(expectedBytes), 0), 1)
            } else {
                fractionCompleted = 0
            }

            progressHandler(ModelDownloadProgress(
                phase: .downloading,
                fractionCompleted: fractionCompleted,
                receivedBytes: bytesReceived,
                expectedBytes: expectedBytes
            ))
        } catch {
            complete(with: error)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        try? fileHandle.close()

        if let error {
            complete(with: error)
            return
        }

        progressHandler(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 1,
            receivedBytes: bytesReceived,
            expectedBytes: expectedBytes
        ))
        complete()
    }

    private var isCompleted: Bool {
        lock.withLock {
            hasCompleted
        }
    }

    private func complete() {
        complete(with: nil)
    }

    private func complete(with error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !hasCompleted else {
                return nil
            }

            hasCompleted = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else {
            return
        }

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

internal final class LiveWhisperCppManager: WhisperCppManaging, @unchecked Sendable {
    private enum RuntimeError: Error {
        case modelNotLoaded
    }

    private let queue = DispatchQueue(label: "personal_scribe.whispercpp.runtime")
    private let library: any WhisperCppLibrary
    private var context: OpaquePointer?
    private var loadedModelPath: String?

    init(library: any WhisperCppLibrary = LiveWhisperCppLibrary()) {
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

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> WhisperCppManagerResult {
        let nThreads = Self.defaultThreadCount()
        return try await enqueue {
            guard let context = self.context else {
                throw RuntimeError.modelNotLoaded
            }

            let text = try self.library.transcribe(
                context: context,
                audioSamples: audioSamples,
                nThreads: nThreads,
                languageHint: languageHint
            )
            return WhisperCppManagerResult(text: text)
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

private struct LiveWhisperCppLibrary: WhisperCppLibrary {
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

    func transcribe(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        // Do NOT set params.detect_language = true. Upstream semantics
        // are "exit after automatically detecting language" (per
        // whisper.cpp's CLI --detect-language help). With language="auto"
        // below, that short-circuits the decoder and returns zero
        // segments — symptom: empty transcripts with ~80ms processing
        // time on multi-second audio.
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

        var text = ""
        let segmentCount = Int(whisper_full_n_segments(context))
        for index in 0..<segmentCount {
            if let segmentText = whisper_full_get_segment_text(context, Int32(index)) {
                text += String(cString: segmentText)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
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
