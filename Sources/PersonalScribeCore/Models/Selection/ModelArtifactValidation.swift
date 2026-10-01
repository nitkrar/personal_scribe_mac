import Foundation

/// Single on-disk validity check for a descriptor's model artifacts:
/// every `requiredRelativePaths` entry exists, `coremldata.bin` files
/// are non-empty, and JSON files parse as an object/array. Lives in
/// Core so both the provider (Session: "is it downloaded?" for the UI)
/// and adapters (Transcription: skip the network download step at
/// prepare time) use the same rule.
public enum ModelArtifactValidation {
    public static func areValid(
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
