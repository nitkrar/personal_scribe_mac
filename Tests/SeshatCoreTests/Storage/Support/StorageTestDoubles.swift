import Foundation
@testable import SeshatCore

struct FixedStorageLocator: StorageLocator {
    let baseDirectory: URL

    func url(for directory: ManagedDirectory) -> URL {
        baseDirectory
            .appendingPathComponent(directory.pathComponent, isDirectory: true)
            .standardizedFileURL
    }

    func ensureDirectoriesExist() throws {}
}

struct FailingAtomicFileWriter: AtomicFileWriter {
    enum Failure: Error, Sendable, Equatable {
        case expectedFailure
    }

    let error: Failure = .expectedFailure

    func replaceItem(
        at destinationURL: URL,
        permissions: Int?,
        writeToTemporaryURL: (URL) throws -> Void
    ) throws {
        throw error
    }
}
