import Foundation

/// Single on-disk validity check for a descriptor's model artifacts:
/// every `requiredRelativePaths` entry exists, `coremldata.bin` files
/// are non-empty, and JSON files parse as an object/array. Lives in
/// Core so the provider (Session: "is it downloaded?" for the UI) and
/// every adapter (Transcription: skip the download step at prepare
/// time — Parakeet, WhisperKit, whisper.cpp) use the same rule.
public enum ModelArtifactValidation {
    public static func areValid(
        in directory: URL,
        descriptor: ModelDescriptor,
        fileManager: FileManager = .default
    ) -> Bool {
        areValid(descriptor.requiredRelativePaths, in: directory, fileManager: fileManager)
    }

    /// Checks each `auxiliaryRepos` folder under `modelsRoot`.
    public static func auxiliaryReposAreValid(
        in modelsRoot: URL,
        descriptor: ModelDescriptor,
        fileManager: FileManager = .default
    ) -> Bool {
        descriptor.auxiliaryRepos.allSatisfy { repo in
            areValid(
                repo.requiredRelativePaths,
                in: modelsRoot.appendingPathComponent(repo.folderName, isDirectory: true),
                fileManager: fileManager
            )
        }
    }

    private static func areValid(
        _ relativePaths: [String],
        in directory: URL,
        fileManager: FileManager
    ) -> Bool {
        let requiredPaths = relativePaths.map {
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
