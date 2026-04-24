import Foundation
import PersonalScribeCore
import PersonalScribeTranscription

public final class ModelBoundTranscriberProvider: ModelBoundTranscriberProviding, @unchecked Sendable {
    private let storageLocator: any StorageLocator
    private let transcriberFactory: @Sendable (ModelDescriptor) -> ModelAwareFluidAudioTranscriber
    private let lock = NSLock()
    private var transcribers: [String: ModelAwareFluidAudioTranscriber] = [:]

    public init(
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.storageLocator = storageLocator
        self.transcriberFactory = { descriptor in
            ModelAwareFluidAudioTranscriber(
                descriptor: descriptor,
                storageLocator: storageLocator
            )
        }
    }

    init(
        storageLocator: any StorageLocator,
        transcriberFactory: @escaping @Sendable (ModelDescriptor) -> ModelAwareFluidAudioTranscriber
    ) {
        self.storageLocator = storageLocator
        self.transcriberFactory = transcriberFactory
    }

    public func transcriber(for descriptor: ModelDescriptor) -> any Transcribing {
        resolvedTranscriber(for: descriptor)
    }

    func isDownloaded(_ descriptor: ModelDescriptor) -> Bool {
        Self.modelArtifactsAreValid(
            in: modelDirectory(for: descriptor),
            descriptor: descriptor
        )
    }

    func download(
        _ descriptor: ModelDescriptor,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try await resolvedTranscriber(for: descriptor).download(progress: progress)
    }

    /// Remove the on-disk artifacts for `descriptor` and drop the cached
    /// transcriber so the next `transcriber(for:)` call rebuilds.
    ///
    /// Ticket #024: delete path for the AI Models tab. Pure file-system
    /// + cache operation — does not consult active selection, last-model
    /// policy, or confirmation state. The caller owns policy.
    public func removeDownloadedFiles(_ descriptor: ModelDescriptor) throws {
        let directory = modelDirectory(for: descriptor)
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
        lock.withLock {
            transcribers[descriptor.id] = nil
        }
    }
}

private extension ModelBoundTranscriberProvider {
    func resolvedTranscriber(for descriptor: ModelDescriptor) -> ModelAwareFluidAudioTranscriber {
        lock.withLock {
            if let existing = transcribers[descriptor.id] {
                return existing
            }

            let transcriber = transcriberFactory(descriptor)
            transcribers[descriptor.id] = transcriber
            return transcriber
        }
    }

    func modelDirectory(for descriptor: ModelDescriptor) -> URL {
        // #024.5: derive the on-disk folder from FluidAudio's source of
        // truth (`Repo.folderName`) via the descriptor's
        // `repoFolderName`. They match by coincidence today; coupling
        // them via this field removes the silent re-download risk if
        // FluidAudio renames a repo's folderName upstream.
        storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
    }

    static func modelArtifactsAreValid(in directory: URL, descriptor: ModelDescriptor) -> Bool {
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

        let vocabURL = directory.appendingPathComponent("parakeet_vocab.json", isDirectory: false)
        guard
            let data = try? Data(contentsOf: vocabURL),
            !data.isEmpty,
            let first = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first,
            first == "{" || first == "["
        else {
            return false
        }

        return true
    }
}
