import Foundation

/// `@unchecked Sendable` is safe here because `FileManager` is the only stored reference and the
/// implementation only uses Apple-documented thread-safe filesystem APIs.
public struct FileManagerAtomicFileWriter: AtomicFileWriter, @unchecked Sendable {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func replaceItem(
        at destinationURL: URL,
        permissions: Int?,
        writeToTemporaryURL: (URL) throws -> Void
    ) throws {
        let destinationParentURL = destinationURL.deletingLastPathComponent().standardizedFileURL
        try fileManager.createDirectory(at: destinationParentURL, withIntermediateDirectories: true)

        let temporaryURL = temporaryReplacementURL(for: destinationURL, in: destinationParentURL)

        do {
            try writeToTemporaryURL(temporaryURL)
            try applyPermissionsIfRequested(permissions, to: temporaryURL)

            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(
                    destinationURL,
                    withItemAt: temporaryURL,
                    backupItemName: nil,
                    options: []
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }

            try applyPermissionsIfRequested(permissions, to: destinationURL)
        } catch {
            cleanupTemporaryItem(at: temporaryURL)
            throw error
        }
    }

    private func temporaryReplacementURL(for destinationURL: URL, in parentURL: URL) -> URL {
        let lastPathComponent = destinationURL.lastPathComponent.isEmpty ? "replacement" : destinationURL.lastPathComponent
        return parentURL
            .appendingPathComponent(".\(lastPathComponent).\(UUID().uuidString).tmp", isDirectory: destinationURL.hasDirectoryPath)
            .standardizedFileURL
    }

    private func applyPermissionsIfRequested(_ permissions: Int?, to url: URL) throws {
        guard let permissions else {
            return
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: permissions)],
            ofItemAtPath: url.path
        )
    }

    private func cleanupTemporaryItem(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }
}
