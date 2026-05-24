@preconcurrency import WhisperKit
import Foundation
import PersonalScribeCore

typealias WhisperKitSleep = @Sendable (Duration) async throws -> Void

protocol WhisperKitManaging: Sendable {
    func downloadAndStage(
        repoID: String,
        matchingPatterns: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws

    func loadModel(
        modelName: String,
        modelFolder: URL,
        tokenizerFolder: URL
    ) async throws

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperKitManagerResult]

    func start() async throws
    func appendAudioSamples(_ audioSamples: [Float]) async throws -> [WhisperKitStreamingState]
    func finish() async throws -> [WhisperKitStreamingState]
    func cleanup() async
}

protocol WhisperKitHubSnapshotting: Sendable {
    func snapshot(
        repoID: String,
        matchingPatterns: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL
}

struct WhisperKitManagerResult: Sendable, Equatable {
    let text: String
}

struct WhisperKitRuntimeHandle: Sendable {
    let transcribeSamples: @Sendable ([Float], DecodingOptions?) async throws -> [WhisperKitManagerResult]
    let start: @Sendable () async throws -> Void
    let appendAudioSamples: @Sendable ([Float]) async throws -> [WhisperKitStreamingState]
    let finish: @Sendable () async throws -> [WhisperKitStreamingState]
    let unloadModels: @Sendable () async -> Void
}

extension HubApiWrapper: WhisperKitHubSnapshotting {
    func snapshot(
        repoID: String,
        matchingPatterns: [String],
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws -> URL {
        try await snapshot(
            from: HubApiWrapper.Repo(id: repoID),
            matching: matchingPatterns,
            progressHandler: progressHandler
        )
    }
}

public actor WhisperKitAdapter: Transcriber, StreamingTranscriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any WhisperKitManaging
    private let logger: PersonalScribeLogger?
    private let idleUnloadDelay: Duration
    private let sleep: WhisperKitSleep
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private let fileManager: FileManager
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
            manager: LiveWhisperKitManager(),
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
            manager: LiveWhisperKitManager(),
            logger: logger,
            idleUnloadDelay: .seconds(30)
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any WhisperKitManaging,
        fileManager: FileManager = .default,
        logger: PersonalScribeLogger? = nil,
        idleUnloadDelay: Duration = .seconds(30),
        sleep: @escaping WhisperKitSleep = { try await Task.sleep(for: $0) }
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.logger = logger
        self.idleUnloadDelay = idleUnloadDelay
        self.sleep = sleep
        self.fileManager = fileManager
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
    ) async throws -> PersonalScribeCore.TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let results = try await manager.transcribe(
                audioSamples: audio.samples,
                languageHint: languageHint
            )
            let measuredTotalDuration = startedAt.duration(to: ContinuousClock.now)
            return makeTranscriptionResult(
                from: results,
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

private extension WhisperKitAdapter {
    struct DownloadPlan: Sendable {
        let bundlePatterns: [String]
        let tokenizerRelativePaths: [String]
        let bundleFractionRange: ClosedRange<Double>
        let tokenizerFractionRange: ClosedRange<Double>
    }

    struct StreamingEventSummary {
        var partialCount = 0
        var eouCount = 0
    }

    func performPrepare() async throws {
        let modelDirectory = try modelDirectory()
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
            outcome = "start_failed"
            try await manager.start()
            outcome = "completed"

            var ledger = WhisperKitStreamingLedger()
            var emittedUtteranceCount = 0
            var lastState: WhisperKitStreamingState?
            var firstBuffer: PCMBuffer?

            do {
                for try await buffer in stream {
                    try Task.checkCancellation()
                    try validateStreamShape(buffer, against: firstBuffer)
                    if firstBuffer == nil {
                        firstBuffer = buffer
                    }

                    bufferCount += 1
                    audioDuration += buffer.duration

                    let states = try await manager.appendAudioSamples(buffer.samples)
                    for state in states {
                        guard state != lastState else {
                            continue
                        }
                        lastState = state
                        emitEvents(
                            ledger.consume(state),
                            continuation: continuation,
                            summary: &summary,
                            emittedUtteranceCount: &emittedUtteranceCount
                        )
                    }
                }
            } catch is CancellationError {
                outcome = "cancelled"
                _ = try? await manager.finish()
                continuation.finish()
                return
            } catch let error as PersonalScribeError {
                outcome = "stream_failed"
                _ = try? await manager.finish()
                throw error
            } catch {
                outcome = "stream_failed"
                _ = try? await manager.finish()
                throw PersonalScribeError.transcriptionFailure
            }

            let finalStates: [WhisperKitStreamingState]
            do {
                finalStates = try await manager.finish()
            } catch is CancellationError {
                outcome = "cancelled"
                continuation.finish()
                return
            } catch let error as PersonalScribeError {
                outcome = "finish_failed"
                throw error
            } catch {
                outcome = "finish_failed"
                throw PersonalScribeError.transcriptionFailure
            }

            for state in finalStates {
                guard state != lastState else {
                    continue
                }
                lastState = state
                emitEvents(
                    ledger.consume(state),
                    continuation: continuation,
                    summary: &summary,
                    emittedUtteranceCount: &emittedUtteranceCount
                )
            }

            let finalText = ledger.finalText(fallbackState: lastState)
                .trimmingCharacters(in: .whitespacesAndNewlines)
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

    func emitEvents(
        _ events: [StreamingTranscriptionEvent],
        continuation: AsyncThrowingStream<StreamingTranscriptionEvent, Error>.Continuation,
        summary: inout StreamingEventSummary,
        emittedUtteranceCount: inout Int
    ) {
        for event in events {
            switch event {
            case .partial:
                summary.partialCount += 1
            case .endOfUtterance(let text):
                summary.eouCount += 1
                emittedUtteranceCount += 1
                logger?.info(
                    "streaming_eou_emitted descriptorID=\(descriptor.id) utterance=\(emittedUtteranceCount) chars=\(text.count)"
                )
            case .finalized:
                break
            }

            continuation.yield(event)
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

    func performDownloadIfNeeded(emitFinished: Bool) async throws {
        try storageLocator.ensureDirectoriesExist()
        let modelDirectory = try modelDirectory()

        guard
            !WhisperKitArtifactFilesystem.modelArtifactsAreValid(
                in: modelDirectory,
                descriptor: descriptor,
                fileManager: fileManager
            )
        else {
            if emitFinished {
                progressBroadcaster.emit(.finished)
            }
            return
        }

        guard let tokenizerSource = descriptor.tokenizerSource, !tokenizerSource.isEmpty else {
            throw PersonalScribeError.modelLoadFailure
        }

        let plan = try downloadPlan()
        let stagingDirectory = stagingDirectory()
        let tokenizerDirectory = modelDirectory
            .appendingPathComponent("tokenizer", isDirectory: true)
            .standardizedFileURL
        let broadcaster = progressBroadcaster

        do {
            try cleanupPartialDownload(
                modelDirectory: modelDirectory,
                stagingDirectory: stagingDirectory
            )
            progressBroadcaster.emit(.downloading)

            try await manager.downloadAndStage(
                repoID: descriptor.repository,
                matchingPatterns: plan.bundlePatterns,
                stagingDirectory: stagingDirectory,
                destination: modelDirectory,
                progressHandler: { progress in
                    Self.emitDownloadProgress(
                        progress,
                        fractionRange: plan.bundleFractionRange,
                        broadcaster: broadcaster
                    )
                }
            )

            try await manager.downloadAndStage(
                repoID: tokenizerSource,
                matchingPatterns: plan.tokenizerRelativePaths,
                stagingDirectory: stagingDirectory,
                destination: tokenizerDirectory,
                progressHandler: { progress in
                    Self.emitDownloadProgress(
                        progress,
                        fractionRange: plan.tokenizerFractionRange,
                        broadcaster: broadcaster
                    )
                }
            )
        } catch {
            try? cleanupPartialDownload(
                modelDirectory: modelDirectory,
                stagingDirectory: stagingDirectory
            )
            throw PersonalScribeError.modelLoadFailure
        }

        if emitFinished {
            progressBroadcaster.emit(.finished)
        }
    }

    static func emitDownloadProgress(
        _ progress: Progress,
        fractionRange: ClosedRange<Double>,
        broadcaster: FluidAudioDownloadProgressBroadcaster
    ) {
        let boundedFraction = min(max(progress.fractionCompleted, 0), 1)
        let scaledFraction = fractionRange.lowerBound
            + ((fractionRange.upperBound - fractionRange.lowerBound) * boundedFraction)
        let expectedBytes = progress.totalUnitCount > 0 ? Int64(progress.totalUnitCount) : nil

        broadcaster.emit(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: scaledFraction,
            receivedBytes: Int64(max(progress.completedUnitCount, 0)),
            expectedBytes: expectedBytes
        ))
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func stagingDirectory() -> URL {
        storageLocator
            .url(for: .models)
            .appendingPathComponent(".staging", isDirectory: true)
            .appendingPathComponent(descriptor.id, isDirectory: true)
            .standardizedFileURL
    }

    func downloadPlan() throws -> DownloadPlan {
        let tokenizerRelativePaths = descriptor.requiredRelativePaths
            .filter { $0.hasPrefix("tokenizer/") }
            .map { String($0.dropFirst("tokenizer/".count)) }
        let bundlePatterns = ["\(descriptor.repoFolderName)/*"]

        guard
            !descriptor.repoFolderName.isEmpty,
            !tokenizerRelativePaths.isEmpty
        else {
            throw PersonalScribeError.modelLoadFailure
        }

        return DownloadPlan(
            bundlePatterns: bundlePatterns,
            tokenizerRelativePaths: tokenizerRelativePaths,
            bundleFractionRange: 0...0.95,
            tokenizerFractionRange: 0.95...1
        )
    }

    func cleanupPartialDownload(
        modelDirectory: URL,
        stagingDirectory: URL
    ) throws {
        if fileManager.fileExists(atPath: modelDirectory.path) {
            try fileManager.removeItem(at: modelDirectory)
        }

        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try fileManager.removeItem(at: stagingDirectory)
        }
    }

    func makeTranscriptionResult(
        from results: [WhisperKitManagerResult],
        audioDuration: Duration,
        processingDuration: Duration
    ) -> PersonalScribeCore.TranscriptionResult {
        let mergedText = results
            .map(\.text)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return PersonalScribeCore.TranscriptionResult(
            text: mergedText,
            audioDuration: audioDuration,
            processingDuration: processingDuration
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

    static func milliseconds(from duration: Duration) -> Int {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        let seconds = Double(components.seconds) + (Double(components.attoseconds) / attosecondsPerSecond)
        return Int((seconds * 1000).rounded())
    }
}

private enum WhisperKitArtifactFilesystem {
    static func modelArtifactsAreValid(
        in directory: URL,
        descriptor: ModelDescriptor,
        fileManager: FileManager
    ) -> Bool {
        let requiredPaths = descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }

        guard requiredPaths.allSatisfy({ fileManager.fileExists(atPath: $0.path) }) else {
            return false
        }

        for path in requiredPaths where path.lastPathComponent == "coremldata.bin" {
            guard
                let attributes = try? fileManager.attributesOfItem(atPath: path.path),
                let size = attributes[.size] as? NSNumber,
                size.intValue > 0
            else {
                return false
            }
        }

        for path in requiredPaths where path.pathExtension == "json" {
            guard
                let data = try? Data(contentsOf: path),
                !data.isEmpty,
                let first = String(data: data, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .first,
                first == "{" || first == "["
            else {
                return false
            }
        }

        return true
    }
}

internal actor LiveWhisperKitManager: WhisperKitManaging {
    private let fileManager: FileManager
    private let hubFactory: @Sendable (URL) -> any WhisperKitHubSnapshotting
    private let whisperFactory: (WhisperKitConfig) async throws -> WhisperKitRuntimeHandle
    private var whisperKit: WhisperKitRuntimeHandle?

    init(
        fileManager: FileManager = .default,
        hubFactory: @escaping @Sendable (URL) -> any WhisperKitHubSnapshotting = {
            HubApiWrapper(downloadBase: $0)
        },
        whisperFactory: @escaping (WhisperKitConfig) async throws -> WhisperKitRuntimeHandle = { config in
            let audioProcessor = (config.audioProcessor as? BufferFedWhisperKitAudioProcessor)
                ?? BufferFedWhisperKitAudioProcessor()
            config.audioProcessor = audioProcessor

            let whisperKit = try await WhisperKit(config)
            let runtimeBridge = LiveWhisperKitRuntimeBridge(
                whisperKit: whisperKit,
                audioProcessor: audioProcessor
            )

            return WhisperKitRuntimeHandle(
                transcribeSamples: { audioArray, decodeOptions in
                    try await runtimeBridge.transcribeSamples(
                        audioArray: audioArray,
                        decodeOptions: decodeOptions
                    )
                },
                start: {
                    try await runtimeBridge.start()
                },
                appendAudioSamples: { audioSamples in
                    try await runtimeBridge.appendAudioSamples(audioSamples)
                },
                finish: {
                    try await runtimeBridge.finish()
                },
                unloadModels: {
                    await runtimeBridge.unloadModels()
                }
            )
        }
    ) {
        self.fileManager = fileManager
        self.hubFactory = hubFactory
        self.whisperFactory = whisperFactory
    }

    func downloadAndStage(
        repoID: String,
        matchingPatterns: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws {
        try fileManager.createDirectory(
            at: stagingDirectory,
            withIntermediateDirectories: true
        )

        let hub = hubFactory(stagingDirectory)
        let snapshotRoot = try await hub.snapshot(
            repoID: repoID,
            matchingPatterns: matchingPatterns ?? [],
            progressHandler: progressHandler
        )
        let snapshotLeaf = resolvedSnapshotLeaf(
            snapshotRoot: snapshotRoot,
            matchingPatterns: matchingPatterns
        )

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }

        do {
            try fileManager.moveItem(at: snapshotLeaf, to: destination)
        } catch {
            try fileManager.copyItem(at: snapshotLeaf, to: destination)
            try fileManager.removeItem(at: snapshotLeaf)
        }

        try? fileManager.removeItem(at: stagingDirectory)
    }

    func loadModel(
        modelName: String,
        modelFolder: URL,
        tokenizerFolder: URL
    ) async throws {
        if whisperKit != nil {
            await cleanup()
        }

        let config = WhisperKitConfig(
            model: modelName,
            modelFolder: modelFolder.path,
            tokenizerFolder: tokenizerFolder,
            audioProcessor: BufferFedWhisperKitAudioProcessor(),
            verbose: false,
            logLevel: .none,
            prewarm: false,
            load: true,
            download: false,
            useBackgroundDownloadSession: false
        )
        whisperKit = try await whisperFactory(config)
    }

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> [WhisperKitManagerResult] {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        let decodeOptions = languageHint.map { DecodingOptions(language: $0) }
        return try await whisperKit.transcribeSamples(audioSamples, decodeOptions)
    }

    func start() async throws {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        try await whisperKit.start()
    }

    func appendAudioSamples(_ audioSamples: [Float]) async throws -> [WhisperKitStreamingState] {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        return try await whisperKit.appendAudioSamples(audioSamples)
    }

    func finish() async throws -> [WhisperKitStreamingState] {
        guard let whisperKit else {
            throw PersonalScribeError.modelLoadFailure
        }

        return try await whisperKit.finish()
    }

    func cleanup() async {
        if let whisperKit {
            await whisperKit.unloadModels()
        }
        self.whisperKit = nil
    }

    private func resolvedSnapshotLeaf(
        snapshotRoot: URL,
        matchingPatterns: [String]?
    ) -> URL {
        guard
            let matchingPatterns,
            !matchingPatterns.isEmpty
        else {
            return snapshotRoot
        }

        let topLevelComponents = matchingPatterns.compactMap { path -> String? in
            guard path.contains("/") else {
                return nil
            }
            return path.split(separator: "/", maxSplits: 1).first.map(String.init)
        }

        guard
            let component = topLevelComponents.first,
            !component.isEmpty,
            topLevelComponents.allSatisfy({ $0 == component })
        else {
            return snapshotRoot
        }

        return snapshotRoot
            .appendingPathComponent(component, isDirectory: true)
            .standardizedFileURL
    }
}

private actor LiveWhisperKitRuntimeBridge {
    private let whisperKit: WhisperKit
    private let audioProcessor: BufferFedWhisperKitAudioProcessor
    private var transcriber: AudioStreamTranscriber?
    private var transcriberTask: Task<Void, Error>?
    private var pendingStates: [WhisperKitStreamingState] = []
    private var latestState: WhisperKitStreamingState?

    init(
        whisperKit: WhisperKit,
        audioProcessor: BufferFedWhisperKitAudioProcessor
    ) {
        self.whisperKit = whisperKit
        self.audioProcessor = audioProcessor
    }

    func transcribeSamples(
        audioArray: [Float],
        decodeOptions: DecodingOptions?
    ) async throws -> [WhisperKitManagerResult] {
        let results = try await whisperKit.transcribe(
            audioArray: audioArray,
            decodeOptions: decodeOptions
        )
        return results.map { WhisperKitManagerResult(text: $0.text) }
    }

    func start() async throws {
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
        guard transcriberTask != nil else {
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
    }

    func unloadModels() async {
        await cleanup()
        await whisperKit.unloadModels()
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
