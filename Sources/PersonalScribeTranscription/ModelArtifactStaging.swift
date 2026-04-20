import Foundation
import PersonalScribeCore

public enum ModelArtifactStaging {
    public static func stagingDirectory(base: URL, descriptor: ModelDescriptor) -> URL {
        base.appendingPathComponent("\(descriptor.id)-staging", isDirectory: true)
    }

    public static func requiredModelPaths(in directory: URL, descriptor: ModelDescriptor) -> [URL] {
        descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }
    }

    public static func modelsExist(in directory: URL, descriptor: ModelDescriptor) -> Bool {
        let fileManager = FileManager.default
        return requiredModelPaths(in: directory, descriptor: descriptor)
            .allSatisfy { fileManager.fileExists(atPath: $0.path) }
    }

    public static func normalizedProgress(
        _ snapshot: ModelDownloadProgress,
        current: ModelDownloadProgress
    ) -> ModelDownloadProgress {
        guard snapshot.phase == .downloading, current.phase == .downloading else {
            return snapshot
        }

        return .init(
            phase: .downloading,
            fractionCompleted: max(snapshot.fractionCompleted, current.fractionCompleted),
            receivedBytes: max(snapshot.receivedBytes, current.receivedBytes),
            expectedBytes: snapshot.expectedBytes ?? current.expectedBytes
        )
    }

    public static func modelArtifactsAreValid(
        in directory: URL,
        descriptor: ModelDescriptor
    ) -> Bool {
        guard modelsExist(in: directory, descriptor: descriptor) else {
            return false
        }

        let fileManager = FileManager.default

        for path in requiredModelPaths(in: directory, descriptor: descriptor)
        where path.lastPathComponent == "coremldata.bin" {
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
            let contents = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .first,
            contents == "{" || contents == "["
        else {
            return false
        }

        return true
    }
}
