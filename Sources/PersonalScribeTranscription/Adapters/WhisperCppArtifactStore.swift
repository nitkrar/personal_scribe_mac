import Foundation
import PersonalScribeCore

struct WhisperCppArtifactStore: @unchecked Sendable {
    let descriptor: ModelDescriptor
    let storageLocator: any StorageLocator
    let fileManager: FileManager

    func downloadIfNeeded(
        downloader: any WhisperCppDownloading,
        progressBroadcaster: FluidAudioDownloadProgressBroadcaster,
        emitFinished: Bool
    ) async throws {
        try storageLocator.ensureDirectoriesExist()
        let modelDirectory = try self.modelDirectory()
        let modelFileURL = try self.modelFileURL()
        let temporaryFileURL = temporaryModelFileURL(for: modelFileURL)

        guard !Self.modelArtifactsAreValid(
            in: modelDirectory,
            descriptor: descriptor,
            fileManager: fileManager
        ) else {
            if emitFinished {
                progressBroadcaster.emit(.finished)
            }
            return
        }

        try fileManager.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: modelFileURL.path) {
            try? fileManager.removeItem(at: modelFileURL)
        }
        if fileManager.fileExists(atPath: temporaryFileURL.path) {
            try? fileManager.removeItem(at: temporaryFileURL)
        }

        let remoteURL = try remoteModelURL()
        progressBroadcaster.emit(.downloading)

        do {
            try await downloader.download(
                from: remoteURL,
                to: temporaryFileURL,
                progressHandler: { snapshot in
                    progressBroadcaster.emit(snapshot)
                }
            )
            try moveDownloadedFileIntoPlace(
                temporaryFileURL: temporaryFileURL,
                modelFileURL: modelFileURL
            )
        } catch {
            try? cleanupPartialDownload(
                temporaryFileURL: temporaryFileURL,
                modelFileURL: modelFileURL
            )
            throw PersonalScribeError.modelLoadFailure
        }

        if emitFinished {
            progressBroadcaster.emit(.finished)
        }
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

    func modelFileURL() throws -> URL {
        try modelDirectory()
            .appendingPathComponent(requiredModelFilename(), isDirectory: false)
            .standardizedFileURL
    }

    func requiredModelFilename() throws -> String {
        guard descriptor.requiredRelativePaths.count == 1 else {
            throw PersonalScribeError.modelLoadFailure
        }

        let filename = descriptor.requiredRelativePaths[0]
        guard
            !filename.isEmpty,
            !filename.contains("/"),
            descriptor.tokenizerSource == nil,
            descriptor.auxiliaryRepoFolderNames.isEmpty
        else {
            throw PersonalScribeError.modelLoadFailure
        }

        return filename
    }

    func remoteModelURL() throws -> URL {
        descriptor.resolveURL(for: try requiredModelFilename())
    }

    func temporaryModelFileURL(for modelFileURL: URL) -> URL {
        modelFileURL
            .appendingPathExtension("download")
            .standardizedFileURL
    }

    func moveDownloadedFileIntoPlace(
        temporaryFileURL: URL,
        modelFileURL: URL
    ) throws {
        if fileManager.fileExists(atPath: modelFileURL.path) {
            _ = try fileManager.replaceItemAt(
                modelFileURL,
                withItemAt: temporaryFileURL
            )
            return
        }

        try fileManager.moveItem(at: temporaryFileURL, to: modelFileURL)
    }

    func cleanupPartialDownload(
        temporaryFileURL: URL,
        modelFileURL: URL
    ) throws {
        if fileManager.fileExists(atPath: temporaryFileURL.path) {
            try fileManager.removeItem(at: temporaryFileURL)
        }

        if fileManager.fileExists(atPath: modelFileURL.path) {
            try fileManager.removeItem(at: modelFileURL)
        }
    }

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
