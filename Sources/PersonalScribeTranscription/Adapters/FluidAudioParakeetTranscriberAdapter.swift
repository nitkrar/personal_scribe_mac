import FluidAudio
import Foundation
import PersonalScribeCore

public actor FluidAudioParakeetTranscriberAdapter: Transcriber {
    public nonisolated let capabilities = TranscriberCapabilities(
        providesTokenTimings: true,
        providesConfidence: true,
        providesPerformanceMetrics: true,
        providesCustomVocabulary: true
    )

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any FluidAudioParakeetManaging
    private let runtimeVariantResult: Result<RuntimeVariant, ModelSelectionError>
    private let progressBroadcaster = FluidAudioParakeetDownloadProgressBroadcaster()
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?
    private var loadDuration: Duration?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveFluidAudioParakeetManager()
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any FluidAudioParakeetManaging
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.runtimeVariantResult = Self.resolveRuntimeVariant(for: descriptor)
    }

    public func prepare() async throws {
        if hasPreparedModel {
            return
        }

        if let prepareTask {
            return try await prepareTask.value
        }

        let runtimeVariant = try resolvedRuntimeVariant()
        let task = Task {
            try await self.performPrepare(runtimeVariant: runtimeVariant)
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
        } catch {
            prepareTask = nil
            progressBroadcaster.update(Self.idleSnapshot)
            throw error
        }
    }

    public func downloadIfNeeded() async throws {
        let runtimeVariant = try resolvedRuntimeVariant()
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL

        do {
            try await manager.downloadIfNeeded(
                to: modelsRoot,
                version: runtimeVariant.asrModelVersion,
                progressHandler: { snapshot in
                    self.progressBroadcaster.update(Self.map(snapshot))
                }
            )
        } catch {
            progressBroadcaster.update(Self.idleSnapshot)
            throw PersonalScribeError.modelLoadFailure
        }

        progressBroadcaster.update(Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot))
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let managerResult = try await manager.transcribe(samples: audio.samples)
            let measuredTotalDuration = startedAt.duration(to: ContinuousClock.now)
            return makeTranscriptionResult(
                from: managerResult,
                audioDuration: audio.duration,
                measuredTotalDuration: measuredTotalDuration
            )
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }
    }
}

extension FluidAudioParakeetTranscriberAdapter {
    private enum RuntimeVariant: Sendable {
        case parakeetTDT06Bv2
        case parakeetTDT06Bv3
        case parakeetTDTCTC110M

        init(descriptor: ModelDescriptor) throws {
            switch descriptor.id {
            case BuiltInModelCatalog.parakeetTDT06Bv2.id:
                self = .parakeetTDT06Bv2
            case BuiltInModelCatalog.parakeetTDT06Bv3.id:
                self = .parakeetTDT06Bv3
            case BuiltInModelCatalog.parakeetTDTCTC110M.id:
                self = .parakeetTDTCTC110M
            default:
                throw ModelSelectionError.unknownVoiceModelID(descriptor.id)
            }
        }

        var asrModelVersion: AsrModelVersion {
            switch self {
            case .parakeetTDT06Bv2:
                .v2
            case .parakeetTDT06Bv3:
                .v3
            case .parakeetTDTCTC110M:
                .tdtCtc110m
            }
        }
    }

    static let idleSnapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    private static func resolveRuntimeVariant(
        for descriptor: ModelDescriptor
    ) -> Result<RuntimeVariant, ModelSelectionError> {
        do {
            return .success(try RuntimeVariant(descriptor: descriptor))
        } catch let error as ModelSelectionError {
            return .failure(error)
        } catch {
            return .failure(.unknownVoiceModelID(descriptor.id))
        }
    }

    private func resolvedRuntimeVariant() throws -> RuntimeVariant {
        try runtimeVariantResult.get()
    }

    private func performPrepare(runtimeVariant: RuntimeVariant) async throws {
        let modelDirectory = try modelDirectory()
        try storageLocator.ensureDirectoriesExist()
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL
        let startedAt = ContinuousClock.now
        let progressBroadcaster = self.progressBroadcaster

        do {
            try await manager.downloadIfNeeded(
                to: modelsRoot,
                version: runtimeVariant.asrModelVersion,
                progressHandler: { snapshot in
                    self.progressBroadcaster.update(Self.map(snapshot))
                }
            )
            try await manager.loadModel(
                from: modelDirectory,
                version: runtimeVariant.asrModelVersion,
                progressHandler: { snapshot in
                    self.progressBroadcaster.update(Self.map(snapshot))
                }
            )
            loadDuration = startedAt.duration(to: ContinuousClock.now)
        } catch {
            throw PersonalScribeError.modelLoadFailure
        }

        progressBroadcaster.update(Self.finishedSnapshot(from: progressBroadcaster.currentSnapshot))
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func makeTranscriptionResult(
        from managerResult: FluidAudioParakeetManagerResult,
        audioDuration: Duration,
        measuredTotalDuration: Duration
    ) -> TranscriptionResult {
        let tokenTimings = managerResult.tokenTimings
        let confidence = managerResult.confidence ?? Self.averageConfidence(from: tokenTimings)
        let performanceMetrics = TranscriberPerformanceMetrics(
            loadDuration: managerResult.performanceMetrics?.loadDuration ?? loadDuration,
            encodeDuration: managerResult.performanceMetrics?.encodeDuration,
            decodeDuration: managerResult.performanceMetrics?.decodeDuration,
            totalDuration: managerResult.performanceMetrics?.totalDuration ?? measuredTotalDuration
        )

        return TranscriptionResult(
            text: managerResult.text,
            audioDuration: audioDuration,
            processingDuration: managerResult.processingDuration ?? measuredTotalDuration,
            confidence: confidence,
            tokenTimings: tokenTimings,
            performanceMetrics: performanceMetrics,
            ctcDetectedTerms: managerResult.ctcDetectedTerms,
            ctcAppliedTerms: managerResult.ctcAppliedTerms
        )
    }

    static func averageConfidence(from tokenTimings: [PersonalScribeCore.TokenTiming]?) -> Float? {
        guard let tokenTimings else {
            return nil
        }

        let confidences = tokenTimings.compactMap(\.confidence)
        guard !confidences.isEmpty else {
            return nil
        }

        return confidences.reduce(0, +) / Float(confidences.count)
    }

    static func map(_ snapshot: DownloadUtils.DownloadProgress) -> ModelDownloadProgress {
        switch snapshot.phase {
        case .listing, .downloading:
            return .init(
                phase: .downloading,
                fractionCompleted: snapshot.fractionCompleted,
                receivedBytes: 0,
                expectedBytes: nil
            )
        case .compiling:
            return .init(
                phase: .loading,
                fractionCompleted: snapshot.fractionCompleted,
                receivedBytes: 0,
                expectedBytes: nil
            )
        }
    }

    static func finishedSnapshot(from snapshot: ModelDownloadProgress) -> ModelDownloadProgress {
        .init(
            phase: .finished,
            fractionCompleted: 1,
            receivedBytes: snapshot.receivedBytes,
            expectedBytes: snapshot.expectedBytes
        )
    }
}

protocol FluidAudioParakeetManaging: Sendable {
    func downloadIfNeeded(
        to directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws

    func loadModel(
        from directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws

    func transcribe(samples: [Float]) async throws -> FluidAudioParakeetManagerResult
}

struct FluidAudioParakeetManagerResult: Sendable, Equatable {
    let text: String
    let processingDuration: Duration?
    let confidence: Float?
    let tokenTimings: [PersonalScribeCore.TokenTiming]?
    let performanceMetrics: TranscriberPerformanceMetrics?
    let ctcDetectedTerms: [String]?
    let ctcAppliedTerms: [String]?

    init(
        text: String,
        processingDuration: Duration? = nil,
        confidence: Float? = nil,
        tokenTimings: [PersonalScribeCore.TokenTiming]? = nil,
        performanceMetrics: TranscriberPerformanceMetrics? = nil,
        ctcDetectedTerms: [String]? = nil,
        ctcAppliedTerms: [String]? = nil
    ) {
        self.text = text
        self.processingDuration = processingDuration
        self.confidence = confidence
        self.tokenTimings = tokenTimings
        self.performanceMetrics = performanceMetrics
        self.ctcDetectedTerms = ctcDetectedTerms
        self.ctcAppliedTerms = ctcAppliedTerms
    }
}

internal actor LiveFluidAudioParakeetManager: FluidAudioParakeetManaging {
    private let managerFactory: @Sendable () -> AsrManager
    private var manager: AsrManager?

    init(
        managerFactory: @escaping @Sendable () -> AsrManager = { AsrManager(config: .default) }
    ) {
        self.managerFactory = managerFactory
    }

    func downloadIfNeeded(
        to directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        // Bypass `AsrModels.download(to:)` — its internal
        // `targetDir.deletingLastPathComponent()` dance does not match
        // the path our descriptor's `repoFolderName` resolves to.
        // `DownloadUtils.downloadRepo` cleanly appends `repo.folderName`
        // to `to:`, landing files at the same leaf our descriptor uses.
        // (`AsrModelVersion.repo` is internal in FluidAudio, so we
        // mirror the mapping here.)
        let repo: Repo
        switch version {
        case .v2: repo = .parakeetV2
        case .v3: repo = .parakeet
        case .tdtCtc110m: repo = .parakeetTdtCtc110m
        case .ctcZhCn: repo = .parakeetCtcZhCn
        case .ctcJa: repo = .parakeetCtcJa
        case .tdtJa: repo = .parakeetCtcJa  // mirrors FluidAudio's mapping (TDT v2 uploaded to CTC repo)
        @unknown default: repo = .parakeet
        }
        try await DownloadUtils.downloadRepo(
            repo,
            to: directory,
            progressHandler: progressHandler
        )
    }

    func loadModel(
        from directory: URL,
        version: AsrModelVersion,
        progressHandler: DownloadUtils.ProgressHandler?
    ) async throws {
        let models = try await AsrModels.load(
            from: directory,
            version: version,
            progressHandler: progressHandler
        )
        try await resolvedManager().loadModels(models)
    }

    func transcribe(samples: [Float]) async throws -> FluidAudioParakeetManagerResult {
        let result = try await resolvedManager().transcribe(samples, source: .microphone)
        return FluidAudioParakeetResultExtractor.extract(from: result)
    }

    private func resolvedManager() -> AsrManager {
        if let manager {
            return manager
        }

        let manager = managerFactory()
        self.manager = manager
        return manager
    }
}

private enum FluidAudioParakeetResultExtractor {
    // Keep the live `AsrManager` bridge isolated here so the adapter can
    // stay testable through the `FluidAudioParakeetManaging` seam.
    static func extract(from rawResult: Any) -> FluidAudioParakeetManagerResult {
        let tokenTimings = tokenTimings(from: rawResult)
        return FluidAudioParakeetManagerResult(
            text: stringValue(forLabels: ["text", "transcript"], in: rawResult) ?? "",
            processingDuration: durationValue(
                forLabels: ["processingDuration", "processingTime", "totalDuration", "totalTime"],
                in: rawResult
            ),
            confidence: floatValue(forLabels: ["confidence", "score"], in: rawResult)
                ?? FluidAudioParakeetTranscriberAdapter.averageConfidence(from: tokenTimings),
            tokenTimings: tokenTimings,
            performanceMetrics: performanceMetrics(from: rawResult),
            ctcDetectedTerms: stringArrayValue(
                forLabels: ["ctcDetectedTerms", "detectedTerms", "detectedCustomVocabulary"],
                in: rawResult
            ),
            ctcAppliedTerms: stringArrayValue(
                forLabels: ["ctcAppliedTerms", "appliedTerms", "appliedCustomVocabulary"],
                in: rawResult
            )
        )
    }

    private static func tokenTimings(from source: Any) -> [PersonalScribeCore.TokenTiming]? {
        guard
            let rawTokenCollection = directValue(
                forLabels: ["tokenTimings", "tokens", "timings", "tokenTimestamps"],
                in: source
            )
        else {
            return nil
        }

        let timings = collectionValues(from: rawTokenCollection).compactMap { item -> PersonalScribeCore.TokenTiming? in
            let token = stringValue(forLabels: ["token", "text", "value"], in: item)
            let start = durationValue(
                forLabels: ["start", "startTime", "startOffset", "startSeconds"],
                in: item
            )
            let end = durationValue(
                forLabels: ["end", "endTime", "endOffset", "endSeconds"],
                in: item
            )
            let duration = durationValue(forLabels: ["duration", "length"], in: item)

            guard let token else {
                return nil
            }

            let resolvedStart = start ?? .zero
            let resolvedEnd = end ?? duration.map { resolvedStart + $0 } ?? resolvedStart

            return PersonalScribeCore.TokenTiming(
                token: token,
                start: resolvedStart,
                end: resolvedEnd,
                confidence: floatValue(forLabels: ["confidence", "score"], in: item)
            )
        }

        return timings.isEmpty ? nil : timings
    }

    private static func performanceMetrics(from source: Any) -> TranscriberPerformanceMetrics? {
        let nestedMetrics = directValue(
            forLabels: ["performanceMetrics", "metrics", "performance", "timings"],
            in: source
        )

        let loadDuration = durationValue(
            forLabels: ["loadDuration", "modelLoadDuration"],
            in: nestedMetrics ?? source
        )
        let encodeDuration = durationValue(
            forLabels: ["encodeDuration", "encoderDuration", "encodingDuration"],
            in: nestedMetrics ?? source
        )
        let decodeDuration = durationValue(
            forLabels: ["decodeDuration", "decoderDuration", "decodingDuration"],
            in: nestedMetrics ?? source
        )
        let totalDuration = durationValue(
            forLabels: ["totalDuration", "processingDuration", "processingTime", "totalTime"],
            in: nestedMetrics ?? source
        )

        guard
            loadDuration != nil
                || encodeDuration != nil
                || decodeDuration != nil
                || totalDuration != nil
        else {
            return nil
        }

        return TranscriberPerformanceMetrics(
            loadDuration: loadDuration,
            encodeDuration: encodeDuration,
            decodeDuration: decodeDuration,
            totalDuration: totalDuration
        )
    }

    private static func stringValue(forLabels labels: [String], in source: Any) -> String? {
        guard let value = directValue(forLabels: labels, in: source) else {
            return nil
        }

        if let string = unwrap(value) as? String {
            return string
        }

        return nil
    }

    private static func floatValue(forLabels labels: [String], in source: Any) -> Float? {
        guard let value = directValue(forLabels: labels, in: source) else {
            return nil
        }

        return float(from: value)
    }

    private static func durationValue(forLabels labels: [String], in source: Any) -> Duration? {
        guard let value = directValue(forLabels: labels, in: source) else {
            return nil
        }

        return duration(from: value)
    }

    private static func stringArrayValue(forLabels labels: [String], in source: Any) -> [String]? {
        guard let value = directValue(forLabels: labels, in: source) else {
            return nil
        }

        let strings = collectionValues(from: value).compactMap { item -> String? in
            if let string = unwrap(item) as? String {
                return string
            }

            return stringValue(forLabels: ["term", "text", "value"], in: item)
        }

        return strings.isEmpty ? nil : strings
    }

    private static func directValue(forLabels labels: [String], in source: Any) -> Any? {
        let mirror = Mirror(reflecting: source)
        let normalizedLabels = Set(labels.map { $0.lowercased() })

        for child in mirror.children {
            guard let label = child.label?.lowercased() else {
                continue
            }

            if normalizedLabels.contains(label) {
                return unwrap(child.value)
            }
        }

        return nil
    }

    private static func unwrap(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else {
            return value
        }

        return mirror.children.first?.value
    }

    private static func collectionValues(from value: Any) -> [Any] {
        if let strings = unwrap(value) as? [String] {
            return strings.map { $0 }
        }

        let unwrapped = unwrap(value) ?? value
        let mirror = Mirror(reflecting: unwrapped)
        guard mirror.displayStyle == .collection else {
            return [unwrapped]
        }

        return mirror.children.compactMap { unwrap($0.value) }
    }

    private static func float(from value: Any) -> Float? {
        let unwrapped = unwrap(value) ?? value

        switch unwrapped {
        case let value as Float:
            return value
        case let value as Double:
            return Float(value)
        case let value as Int:
            return Float(value)
        case let value as NSNumber:
            return value.floatValue
        default:
            return nil
        }
    }

    private static func duration(from value: Any) -> Duration? {
        let unwrapped = unwrap(value) ?? value

        if let duration = unwrapped as? Duration {
            return duration
        }

        if let seconds = float(from: unwrapped) {
            return .seconds(Double(seconds))
        }

        if
            let seconds = directValue(
                forLabels: ["seconds", "time", "timeSeconds", "totalSeconds"],
                in: unwrapped
            ).flatMap(float(from:))
        {
            return .seconds(Double(seconds))
        }

        if
            let milliseconds = directValue(
                forLabels: ["milliseconds", "timeMs", "totalMilliseconds"],
                in: unwrapped
            ).flatMap(float(from:))
        {
            return .milliseconds(Int(milliseconds.rounded()))
        }

        return nil
    }
}

private final class FluidAudioParakeetDownloadProgressBroadcaster: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<ModelDownloadProgress>.Continuation] = [:]
    private var snapshot = ModelDownloadProgress(
        phase: .idle,
        fractionCompleted: 0,
        receivedBytes: 0,
        expectedBytes: nil
    )

    func stream() -> AsyncStream<ModelDownloadProgress> {
        AsyncStream { continuation in
            let identifier = UUID()
            let initial = lock.withLock { () -> ModelDownloadProgress in
                continuations[identifier] = continuation
                return snapshot
            }

            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock {
                    self.continuations.removeValue(forKey: identifier)
                }
            }
            continuation.yield(initial)
        }
    }

    func update(_ snapshot: ModelDownloadProgress) {
        let continuations = lock.withLock { () -> [AsyncStream<ModelDownloadProgress>.Continuation] in
            self.snapshot = snapshot
            return Array(self.continuations.values)
        }

        for continuation in continuations {
            continuation.yield(snapshot)
        }
    }

    var currentSnapshot: ModelDownloadProgress {
        lock.withLock { snapshot }
    }
}
