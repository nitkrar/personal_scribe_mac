@preconcurrency import WhisperKit
import Foundation
import PersonalScribeCore

struct WhisperKitStreamingState: Sendable, Equatable {
    let confirmedSegments: [TranscriptionSegment]
    let unconfirmedSegments: [TranscriptionSegment]
}

protocol WhisperKitStreamingManaging: Sendable {
    func loadModel(
        modelName: String,
        modelFolder: URL,
        tokenizerFolder: URL
    ) async throws
    func start() async throws
    func appendAudioSamples(_ audioSamples: [Float]) async throws -> [WhisperKitStreamingState]
    func finish() async throws -> [WhisperKitStreamingState]
    func cleanup() async
}

public actor WhisperKitStreamingTranscriberAdapter: StreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let artifactDownloader: any WhisperKitArtifactDownloading
    private let manager: any WhisperKitStreamingManaging
    private let logger: PersonalScribeLogger
    private let fileManager: FileManager
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription)
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            artifactDownloader: LiveWhisperKitManager(),
            manager: LiveWhisperKitStreamingManager(),
            logger: logger
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        artifactDownloader: any WhisperKitArtifactDownloading,
        manager: any WhisperKitStreamingManaging,
        logger: PersonalScribeLogger = .testing(category: PersonalScribeLogCategory.transcription),
        fileManager: FileManager = .default
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.artifactDownloader = artifactDownloader
        self.manager = manager
        self.logger = logger
        self.fileManager = fileManager
    }

    public func prepare() async throws {
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
        await cleanupPreparedState()
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

private extension WhisperKitStreamingTranscriberAdapter {
    var artifactStore: WhisperKitArtifactStore {
        WhisperKitArtifactStore(
            descriptor: descriptor,
            storageLocator: storageLocator,
            fileManager: fileManager
        )
    }

    func performPrepare() async throws {
        let modelDirectory = try artifactStore.modelDirectory()
        let tokenizerDirectory = modelDirectory
            .appendingPathComponent("tokenizer", isDirectory: true)
            .standardizedFileURL
        try await performDownloadIfNeeded(emitFinished: false)
        progressBroadcaster.emit(.loading)

        do {
            try await manager.loadModel(
                modelName: descriptor.repoFolderName,
                modelFolder: modelDirectory,
                tokenizerFolder: tokenizerDirectory
            )
            progressBroadcaster.emit(.finished)
        } catch {
            await manager.cleanup()
            throw PersonalScribeError.modelLoadFailure
        }
    }

    func performDownloadIfNeeded(emitFinished: Bool) async throws {
        try await artifactStore.downloadIfNeeded(
            downloader: artifactDownloader,
            progressBroadcaster: progressBroadcaster,
            emitFinished: emitFinished
        )
    }

    func executeTranscription(
        from stream: AsyncThrowingStream<PCMBuffer, Error>,
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation
    ) async {
        let diagnosticsContext = StreamingDiagnosticsSession.current
            ?? StreamingDiagnosticsSession.Context()
        var emittedUtteranceCount = 0
        var ledger = WhisperKitStreamingLedger()
        var lastState: WhisperKitStreamingState?
        var audioDuration: Duration = .zero
        var firstBuffer: PCMBuffer?

        do {
            try await prepare()
            try await manager.start()

            do {
                for try await buffer in stream {
                    try Task.checkCancellation()
                    try validateStreamShape(buffer, against: firstBuffer)
                    if firstBuffer == nil {
                        firstBuffer = buffer
                    }

                    audioDuration += buffer.duration
                    let states = try await manager.appendAudioSamples(buffer.samples)
                    for state in states {
                        lastState = state
                        emitEvents(
                            ledger.consume(state),
                            continuation: continuation,
                            diagnosticsContext: diagnosticsContext,
                            emittedUtteranceCount: &emittedUtteranceCount
                        )
                    }
                }
            } catch is CancellationError {
                await cleanupPreparedState()
                continuation.finish()
                return
            } catch let error as PersonalScribeError {
                await cleanupPreparedState()
                continuation.finish(throwing: error)
                return
            } catch {
                await cleanupPreparedState()
                continuation.finish(throwing: PersonalScribeError.transcriptionFailure)
                return
            }

            let finalStates = try await manager.finish()
            for state in finalStates {
                lastState = state
                emitEvents(
                    ledger.consume(state),
                    continuation: continuation,
                    diagnosticsContext: diagnosticsContext,
                    emittedUtteranceCount: &emittedUtteranceCount
                )
            }

            let finalText = ledger.finalText(fallbackState: lastState)
            await cleanupPreparedState()
            continuation.yield(
                .finalized(
                    TranscriptionResult(
                        text: finalText,
                        audioDuration: audioDuration,
                        processingDuration: .zero
                    )
                )
            )
            continuation.finish()
        } catch is CancellationError {
            await cleanupPreparedState()
            continuation.finish()
        } catch let error as PersonalScribeError {
            await cleanupPreparedState()
            continuation.finish(throwing: error)
        } catch {
            await cleanupPreparedState()
            continuation.finish(throwing: PersonalScribeError.transcriptionFailure)
        }
    }

    func emitEvents(
        _ events: [StreamingTranscriptionEvent],
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        diagnosticsContext: StreamingDiagnosticsSession.Context,
        emittedUtteranceCount: inout Int
    ) {
        for event in events {
            continuation.yield(event)
            guard case let .endOfUtterance(text) = event else {
                continue
            }

            emittedUtteranceCount += 1
            logger.info(
                "streaming_eou_emitted session=\(diagnosticsContext.sessionID) utterance=\(emittedUtteranceCount) ms_since_session_start=\(diagnosticsContext.elapsedMilliseconds()) chars=\(text.count)"
            )
        }
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

    func cleanupPreparedState() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }
}

private struct WhisperKitStreamingLedger {
    private var lastCommittedSegmentEndSeconds: Float = 0
    private var committedUtterances: [String] = []
    private var currentPartialText = ""
    private var lastEmittedPartialText = ""

    mutating func consume(_ state: WhisperKitStreamingState) -> [StreamingTranscriptionEvent] {
        var events: [StreamingTranscriptionEvent] = []
        let newlyConfirmed = state.confirmedSegments.filter {
            $0.end > lastCommittedSegmentEndSeconds
        }
        if let lastConfirmedEnd = newlyConfirmed.last?.end {
            lastCommittedSegmentEndSeconds = max(lastCommittedSegmentEndSeconds, lastConfirmedEnd)
        }

        let stableText = Self.joinedText(newlyConfirmed.map(\.text))
        let emittedStable = !stableText.isEmpty
        if emittedStable {
            committedUtterances.append(stableText)
            currentPartialText = ""
            events.append(.endOfUtterance(text: stableText))
        }

        let partialText = Self.joinedText(state.unconfirmedSegments.map(\.text))
        currentPartialText = partialText
        if partialText.isEmpty {
            lastEmittedPartialText = ""
        } else if emittedStable || partialText != lastEmittedPartialText {
            events.append(.partial(text: partialText))
            lastEmittedPartialText = partialText
        }

        return events
    }

    func finalText(fallbackState: WhisperKitStreamingState?) -> String {
        if let fallbackState {
            let stateText = Self.joinedText(
                (fallbackState.confirmedSegments + fallbackState.unconfirmedSegments).map(\.text)
            )
            if !stateText.isEmpty {
                return stateText
            }
        }

        let pieces = currentPartialText.isEmpty
            ? committedUtterances
            : committedUtterances + [currentPartialText]
        return Self.joinedText(pieces)
    }

    private static func joinedText(_ pieces: [String]) -> String {
        pieces
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { piece in
                piece.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            }
            .joined(separator: " ")
    }
}

internal actor LiveWhisperKitStreamingManager: WhisperKitStreamingManaging {
    private let whisperFactory: (WhisperKitConfig) async throws -> WhisperKit
    private var whisperKit: WhisperKit?
    private var audioProcessor: BufferFedWhisperKitAudioProcessor?
    private var transcriber: AudioStreamTranscriber?
    private var transcriberTask: Task<Void, Error>?
    private var pendingStates: [WhisperKitStreamingState] = []
    private var latestState: WhisperKitStreamingState?
    private var loadedModelName: String?
    private var loadedModelFolder: URL?
    private var loadedTokenizerFolder: URL?

    init(
        whisperFactory: @escaping (WhisperKitConfig) async throws -> WhisperKit = { config in
            try await WhisperKit(config)
        }
    ) {
        self.whisperFactory = whisperFactory
    }

    func loadModel(
        modelName: String,
        modelFolder: URL,
        tokenizerFolder: URL
    ) async throws {
        if loadedModelName == modelName,
           loadedModelFolder == modelFolder,
           loadedTokenizerFolder == tokenizerFolder,
           whisperKit != nil,
           audioProcessor != nil
        {
            return
        }

        await cleanup()

        let audioProcessor = BufferFedWhisperKitAudioProcessor()
        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            audioProcessor: audioProcessor,
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        let whisperKit = try await whisperFactory(config)

        self.audioProcessor = audioProcessor
        self.whisperKit = whisperKit
        self.loadedModelName = modelName
        self.loadedModelFolder = modelFolder
        self.loadedTokenizerFolder = tokenizerFolder
    }

    func start() async throws {
        guard let whisperKit, let audioProcessor else {
            throw PersonalScribeError.modelLoadFailure
        }
        guard transcriberTask == nil else {
            return
        }
        guard let tokenizer = whisperKit.tokenizer else {
            throw PersonalScribeError.modelLoadFailure
        }

        pendingStates.removeAll(keepingCapacity: true)
        latestState = nil

        let transcriber = AudioStreamTranscriber(
            audioEncoder: whisperKit.audioEncoder,
            featureExtractor: whisperKit.featureExtractor,
            segmentSeeker: whisperKit.segmentSeeker,
            textDecoder: whisperKit.textDecoder,
            tokenizer: tokenizer,
            audioProcessor: audioProcessor,
            decodingOptions: DecodingOptions(),
            requiredSegmentsForConfirmation: 2,
            useVAD: false,
            stateChangeCallback: { [weak self] oldState, newState in
                guard
                    oldState.confirmedSegments != newState.confirmedSegments
                        || oldState.unconfirmedSegments != newState.unconfirmedSegments
                else {
                    return
                }

                let snapshot = WhisperKitStreamingState(
                    confirmedSegments: newState.confirmedSegments,
                    unconfirmedSegments: newState.unconfirmedSegments
                )
                Task {
                    await self?.record(snapshot)
                }
            }
        )

        self.transcriber = transcriber
        transcriberTask = Task {
            try await transcriber.startStreamTranscription()
        }
        await Task.yield()
    }

    func appendAudioSamples(_ audioSamples: [Float]) async throws -> [WhisperKitStreamingState] {
        guard let audioProcessor else {
            throw PersonalScribeError.modelLoadFailure
        }

        audioProcessor.append(samples: audioSamples)
        await Task.yield()
        return drainPendingStates()
    }

    func finish() async throws -> [WhisperKitStreamingState] {
        if let transcriber {
            await transcriber.stopStreamTranscription()
        }

        if let task = transcriberTask {
            do {
                try await task.value
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                throw PersonalScribeError.transcriptionFailure
            }
        }

        transcriberTask = nil
        transcriber = nil

        var states = drainPendingStates()
        if let latestState, states.last != latestState {
            states.append(latestState)
        }
        return states
    }

    func cleanup() async {
        if let transcriber {
            await transcriber.stopStreamTranscription()
        }

        if let task = transcriberTask {
            task.cancel()
            _ = try? await task.value
        }

        transcriberTask = nil
        transcriber = nil
        pendingStates.removeAll(keepingCapacity: true)
        latestState = nil

        if let whisperKit {
            await whisperKit.unloadModels()
        }

        whisperKit = nil
        audioProcessor = nil
        loadedModelName = nil
        loadedModelFolder = nil
        loadedTokenizerFolder = nil
    }

    private func record(_ state: WhisperKitStreamingState) {
        latestState = state
        pendingStates.append(state)
    }

    private func drainPendingStates() -> [WhisperKitStreamingState] {
        let states = pendingStates
        pendingStates.removeAll(keepingCapacity: true)
        return states
    }
}
