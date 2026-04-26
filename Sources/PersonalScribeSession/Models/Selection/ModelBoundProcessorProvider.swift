import Foundation
import PersonalScribeCore

public final class ModelBoundProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    private let storageLocator: any StorageLocator
    private let registeredDescriptorsByID: [String: ModelDescriptor]
    private let adapterFactory: @Sendable (ModelDescriptor) -> AdapterRecord
    private let lock = NSLock()
    private var records: [String: AdapterRecord] = [:]

    public init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        let registeredDescriptors = BuiltInModelCatalog.registeredModels
        self.storageLocator = storageLocator
        self.registeredDescriptorsByID = Dictionary(
            uniqueKeysWithValues: registeredDescriptors.map { ($0.id, $0) }
        )
        self.adapterFactory = { descriptor in
            switch descriptor.engine {
            case .parakeetTDT:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: FluidAudioParakeetTranscriberAdapter(
                        descriptor: descriptor,
                        storageLocator: storageLocator
                    )
                )
            case .qwen3ASR:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: FluidAudioQwenTranscriberAdapter(
                        descriptor: descriptor,
                        storageLocator: storageLocator
                    )
                )
            case .parakeetEOU:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    streamingTranscriber: FluidAudioStreamingTranscriberAdapter(
                        descriptor: descriptor,
                        storageLocator: storageLocator
                    )
                )
            case .diarization:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    diarizer: FluidAudioOfflineDiarizerAdapter(
                        descriptor: descriptor,
                        storageLocator: storageLocator
                    )
                )
            }
        }
    }

    init(
        storageLocator: any StorageLocator,
        registeredDescriptors: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        adapterFactory: @escaping @Sendable (ModelDescriptor) -> AdapterRecord
    ) {
        self.storageLocator = storageLocator
        self.registeredDescriptorsByID = Dictionary(
            uniqueKeysWithValues: registeredDescriptors.map { ($0.id, $0) }
        )
        self.adapterFactory = adapterFactory
    }

    public func transcriber(for descriptor: ModelDescriptor) throws -> any Transcriber {
        let canonical = try canonicalDescriptor(for: descriptor)
        let record = try resolvedRecord(for: canonical)
        guard let transcriber = record.transcriber else {
            throw ModelSelectionError.unsupportedKind(
                expected: .asr,
                actual: canonical.engine.kind
            )
        }
        return transcriber
    }

    public func streamingTranscriber(
        for descriptor: ModelDescriptor
    ) throws -> any StreamingTranscriber {
        let canonical = try canonicalDescriptor(for: descriptor)
        let record = try resolvedRecord(for: canonical)
        guard let streamingTranscriber = record.streamingTranscriber else {
            throw ModelSelectionError.unsupportedKind(
                expected: .streamingASR,
                actual: canonical.engine.kind
            )
        }
        return streamingTranscriber
    }

    public func diarizer(for descriptor: ModelDescriptor) throws -> any SpeakerDiarizer {
        let canonical = try canonicalDescriptor(for: descriptor)
        let record = try resolvedRecord(for: canonical)
        guard let diarizer = record.diarizer else {
            throw ModelSelectionError.unsupportedKind(
                expected: .diarization,
                actual: canonical.engine.kind
            )
        }
        return diarizer
    }

    public func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        guard let canonical = registeredDescriptorsByID[descriptor.id] else {
            return false
        }
        return ModelArtifactFilesystem.modelArtifactsAreValid(
            in: modelDirectory(for: canonical),
            descriptor: canonical
        )
    }

    public func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        let canonical = try canonicalDescriptor(for: descriptor)
        let record = try resolvedRecord(for: canonical)
        guard let downloadManager = record.downloadManager else {
            throw ModelSelectionError.descriptorNotRegistered(id: canonical.id)
        }
        try await downloadManager.download(progress: progress)
    }

    public func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {
        let canonical = try canonicalDescriptor(for: descriptor)
        let directory = modelDirectory(for: canonical)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        lock.withLock {
            records[canonical.id] = nil
        }
    }
}

private extension ModelBoundProcessorProvider {
    func canonicalDescriptor(for descriptor: ModelDescriptor) throws -> ModelDescriptor {
        guard let canonical = registeredDescriptorsByID[descriptor.id] else {
            throw ModelSelectionError.descriptorNotRegistered(id: descriptor.id)
        }
        return canonical
    }

    func resolvedRecord(for descriptor: ModelDescriptor) throws -> AdapterRecord {
        let canonical = try canonicalDescriptor(for: descriptor)
        return lock.withLock {
            if let existing = records[canonical.id] {
                return existing
            }

            let record = adapterFactory(canonical)
            records[canonical.id] = record
            return record
        }
    }

    func modelDirectory(for descriptor: ModelDescriptor) -> URL {
        ModelArtifactFilesystem.modelDirectory(
            for: descriptor,
            storageLocator: storageLocator
        )
    }
}

private extension AdapterRecord {
    var downloadManager: (any ModelArtifactDownloadManaging)? {
        if let transcriber, let manager = transcriber as? any ModelArtifactDownloadManaging {
            return manager
        }

        if
            let streamingTranscriber,
            let manager = streamingTranscriber as? any ModelArtifactDownloadManaging
        {
            return manager
        }

        if let diarizer, let manager = diarizer as? any ModelArtifactDownloadManaging {
            return manager
        }

        return nil
    }
}

private protocol ModelArtifactDownloadManaging: ModelLifecycle {
    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}

private enum ModelArtifactFilesystem {
    static func modelDirectory(
        for descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) -> URL {
        storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
    }

    static func materializeArtifacts(
        for descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) throws {
        let directory = modelDirectory(for: descriptor, storageLocator: storageLocator)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for relativePath in descriptor.requiredRelativePaths {
            let fileURL = directory.appendingPathComponent(relativePath, isDirectory: false)
            try fileManager.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let data: Data
            if fileURL.lastPathComponent == "coremldata.bin" {
                data = Data([0x1])
            } else if fileURL.pathExtension == "json" {
                data = Data("{}".utf8)
            } else {
                data = Data("stub".utf8)
            }
            try data.write(to: fileURL)
        }
    }

    static func modelArtifactsAreValid(
        in directory: URL,
        descriptor: ModelDescriptor
    ) -> Bool {
        let requiredPaths = descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
        let fileManager = FileManager.default

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

private final class ProcessorProviderDownloadProgressBroadcaster: @unchecked Sendable {
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
}

private final class ProcessorProviderStubAdapterSupport: @unchecked Sendable {
    let descriptor: ModelDescriptor
    let storageLocator: any StorageLocator
    private let progressBroadcaster = ProcessorProviderDownloadProgressBroadcaster()

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
    }

    func prepare() async throws {
        if ModelArtifactFilesystem.modelArtifactsAreValid(
            in: modelDirectory(),
            descriptor: descriptor
        ) {
            progressBroadcaster.update(Self.finishedProgress)
            return
        }

        try await download { _ in }
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        if ModelArtifactFilesystem.modelArtifactsAreValid(
            in: modelDirectory(),
            descriptor: descriptor
        ) {
            progressBroadcaster.update(Self.finishedProgress)
            progress(Self.finishedProgress)
            return
        }

        let downloading = ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0,
            receivedBytes: 0,
            expectedBytes: nil
        )
        progressBroadcaster.update(downloading)
        progress(downloading)

        try ModelArtifactFilesystem.materializeArtifacts(
            for: descriptor,
            storageLocator: storageLocator
        )

        progressBroadcaster.update(Self.finishedProgress)
        progress(Self.finishedProgress)
    }

    private func modelDirectory() -> URL {
        ModelArtifactFilesystem.modelDirectory(
            for: descriptor,
            storageLocator: storageLocator
        )
    }

    private static let finishedProgress = ModelDownloadProgress(
        phase: .finished,
        fractionCompleted: 1,
        receivedBytes: 0,
        expectedBytes: nil
    )
}

private final class FluidAudioParakeetTranscriberAdapter:
    @unchecked Sendable,
    Transcriber,
    ModelArtifactDownloadManaging
{
    let capabilities = TranscriberCapabilities(
        providesTokenTimings: true,
        providesConfidence: true,
        providesPerformanceMetrics: true,
        providesCustomVocabulary: true
    )

    private let support: ProcessorProviderStubAdapterSupport

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) {
        self.support = ProcessorProviderStubAdapterSupport(
            descriptor: descriptor,
            storageLocator: storageLocator
        )
    }

    func prepare() async throws {
        try await support.prepare()
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        support.modelDownloadProgress()
    }

    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try await support.download(progress: progress)
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            audioDuration: audio.duration,
            processingDuration: .zero
        )
    }
}

private final class FluidAudioQwenTranscriberAdapter:
    @unchecked Sendable,
    Transcriber,
    ModelArtifactDownloadManaging
{
    let capabilities = TranscriberCapabilities()

    private let support: ProcessorProviderStubAdapterSupport

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) {
        self.support = ProcessorProviderStubAdapterSupport(
            descriptor: descriptor,
            storageLocator: storageLocator
        )
    }

    func prepare() async throws {
        try await support.prepare()
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        support.modelDownloadProgress()
    }

    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try await support.download(progress: progress)
    }

    func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult {
        TranscriptionResult(
            text: "",
            audioDuration: audio.duration,
            processingDuration: .zero
        )
    }
}

private final class FluidAudioStreamingTranscriberAdapter:
    @unchecked Sendable,
    StreamingTranscriber,
    ModelArtifactDownloadManaging
{
    let capabilities = TranscriberCapabilities()

    private let support: ProcessorProviderStubAdapterSupport

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) {
        self.support = ProcessorProviderStubAdapterSupport(
            descriptor: descriptor,
            storageLocator: storageLocator
        )
    }

    func prepare() async throws {
        try await support.prepare()
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        support.modelDownloadProgress()
    }

    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try await support.download(progress: progress)
    }

    func transcribe(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                .finalized(
                    TranscriptionResult(
                        text: "",
                        audioDuration: .zero,
                        processingDuration: .zero
                    )
                )
            )
            continuation.finish()
        }
    }
}

private final class FluidAudioOfflineDiarizerAdapter:
    @unchecked Sendable,
    SpeakerDiarizer,
    ModelArtifactDownloadManaging
{
    private let support: ProcessorProviderStubAdapterSupport

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator
    ) {
        self.support = ProcessorProviderStubAdapterSupport(
            descriptor: descriptor,
            storageLocator: storageLocator
        )
    }

    func prepare() async throws {
        try await support.prepare()
    }

    func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        support.modelDownloadProgress()
    }

    func download(
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try await support.download(progress: progress)
    }

    func diarize(
        stream: AsyncThrowingStream<PCMBuffer, Error>
    ) -> AsyncStream<SpeakerDiarizationEvent> {
        AsyncStream { continuation in
            continuation.yield(.terminal([]))
            continuation.finish()
        }
    }
}
