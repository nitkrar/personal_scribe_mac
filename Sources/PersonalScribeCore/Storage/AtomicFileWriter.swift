import Foundation

public protocol AtomicFileWriter: Sendable {
    func replaceItem(
        at destinationURL: URL,
        permissions: Int?,
        writeToTemporaryURL: (URL) throws -> Void
    ) throws
}
