import Foundation

public protocol StorageLocator: Sendable {
    var baseDirectory: URL { get }

    func url(for directory: ManagedDirectory) -> URL
    func ensureDirectoriesExist() throws
}
