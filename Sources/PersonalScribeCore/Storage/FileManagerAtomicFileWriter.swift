import Foundation

/// `@unchecked Sendable` is safe here because the stored `FileManager` is only used through
/// Apple-documented thread-safe filesystem APIs and the injected attributes applier is immutable.
public struct FileManagerAtomicFileWriter: AtomicFileWriter, @unchecked Sendable {
    typealias AttributesApplier = (_ fileManager: FileManager, _ attributes: [FileAttributeKey: Any], _ path: String) throws -> Void

    private let fileManager: FileManager
    private let applyAttributes: AttributesApplier

    public init(fileManager: FileManager = .default) {
        self.init(
            fileManager: fileManager,
            applyAttributes: { fileManager, attributes, path in
                try fileManager.setAttributes(attributes, ofItemAtPath: path)
            }
        )
    }

    init(
        fileManager: FileManager,
        applyAttributes: @escaping AttributesApplier
    ) {
        self.fileManager = fileManager
        self.applyAttributes = applyAttributes
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
                    options: [.usingNewMetadataOnly]
                )
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
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

        try applyAttributes(
            fileManager,
            [.posixPermissions: NSNumber(value: permissions)],
            url.path
        )
    }

    private func cleanupTemporaryItem(at url: URL) {
        guard fileManager.fileExists(atPath: url.path) else {
            return
        }

        try? fileManager.removeItem(at: url)
    }
}
