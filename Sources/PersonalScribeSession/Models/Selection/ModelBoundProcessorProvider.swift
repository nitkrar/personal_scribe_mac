import Foundation
import PersonalScribeCore
import PersonalScribeTranscription

public final class ModelBoundProcessorProvider: ModelBoundProcessorProviding, @unchecked Sendable {
    private let storageLocator: any StorageLocator
    private let registeredDescriptorsByID: [String: ModelDescriptor]
    private let adapterFactory: @Sendable (ModelDescriptor) -> AdapterRecord
    private let lock = NSLock()
    private var records: [String: AdapterRecord] = [:]

    public init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator(),
        logger: PersonalScribeLogger
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
            case .whisperKit:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: WhisperKitTranscriberAdapter(
                        descriptor: descriptor,
                        storageLocator: storageLocator
                    )
                )
            case .whisperCpp:
                return AdapterRecord(
                    descriptorID: descriptor.id,
                    transcriber: WhisperCppTranscriberAdapter(
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
                        storageLocator: storageLocator,
                        logger: logger
                    )
                )
            }
        }
    }

    init(
        storageLocator: any StorageLocator,
        registeredDescriptors: [ModelDescriptor] = BuiltInModelCatalog.registeredModels,
        adapterFactory: @escaping @Sendable (ModelDescriptor) -> AdapterRecord,
        logger: PersonalScribeLogger
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
        let lifecycle = record.lifecycle

        // Real adapters drive the actual download from inside
        // `downloadIfNeeded()` — disk-only, no manager load, no RAM
        // tax for a model the user may never activate. Progress flows
        // via `modelDownloadProgress()` (a hot AsyncStream). Bridge
        // the stream to the callback API for the duration, then
        // synthesize a terminal `.finished` so callers see a
        // completion event regardless of whether the adapter fired one
        // (real adapters skip emission when artifacts are already valid).
        let progressStream = lifecycle.modelDownloadProgress()
        let forwarder = Task {
            for await snapshot in progressStream {
                if Task.isCancelled { return }
                progress(snapshot)
            }
        }
        defer { forwarder.cancel() }

        try await lifecycle.downloadIfNeeded()

        progress(ModelDownloadProgress(
            phase: .finished,
            fractionCompleted: 1,
            receivedBytes: 0,
            expectedBytes: nil
        ))
    }

    public func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {
        let canonical = try canonicalDescriptor(for: descriptor)
        let fileManager = FileManager.default
        let modelsRoot = storageLocator.url(for: .models).standardizedFileURL
        // Primary repo's leaf, plus any auxiliary repos the descriptor
        // declares. Hybrid models (e.g. parakeet-tdt-ctc-110m + its
        // CTC head at parakeet-ctc-110m-coreml) need both removed; if
        // we drop only the primary, the aux bytes orphan on disk and
        // the user thinks "Delete" worked when ~98MB stays behind.
        let leaves: [URL] = [modelDirectory(for: canonical)] + canonical.auxiliaryRepoFolderNames.map { folder in
            modelsRoot.appendingPathComponent(folder, isDirectory: true).standardizedFileURL
        }
        for leaf in leaves where fileManager.fileExists(atPath: leaf.path) {
            try fileManager.removeItem(at: leaf)
        }
        lock.withLock {
            records[canonical.id] = nil
        }
    }

    public func evict(_ descriptor: ModelDescriptor) {
        guard let canonical = registeredDescriptorsByID[descriptor.id] else {
            return
        }
        let lifecycle = lock.withLock { () -> (any ModelLifecycle)? in
            records.removeValue(forKey: canonical.id)?.lifecycle
        }
        guard let lifecycle else {
            return
        }
        Task {
            await lifecycle.cleanup()
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
