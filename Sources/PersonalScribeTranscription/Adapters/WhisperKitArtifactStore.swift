import Foundation
import PersonalScribeCore

protocol WhisperKitArtifactDownloading: Sendable {
    func downloadAndStage(
        repoID: String,
        matchingPatterns: [String]?,
        stagingDirectory: URL,
        destination: URL,
        progressHandler: @escaping @Sendable (Progress) -> Void
    ) async throws
}

struct WhisperKitArtifactStore: @unchecked Sendable {
    struct DownloadPlan: Sendable {
        let bundlePatterns: [String]
        let tokenizerRelativePaths: [String]
        let bundleFractionRange: ClosedRange<Double>
        let tokenizerFractionRange: ClosedRange<Double>
    }

    let descriptor: ModelDescriptor
    let storageLocator: any StorageLocator
    let fileManager: FileManager

    func downloadIfNeeded(
        downloader: any WhisperKitArtifactDownloading,
        progressBroadcaster: FluidAudioDownloadProgressBroadcaster,
        emitFinished: Bool
    ) async throws {
        try storageLocator.ensureDirectoriesExist()
        let modelDirectory = try self.modelDirectory()

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
        let stagingDirectory = self.stagingDirectory()
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

            try await downloader.downloadAndStage(
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

            try await downloader.downloadAndStage(
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
}

enum WhisperKitArtifactFilesystem {
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
