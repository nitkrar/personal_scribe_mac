import Foundation
import XCTest
@testable import SeshatCore

final class AtomicFileWriterTests: XCTestCase {
    private enum TestError: Error, Equatable {
        case expectedFailure
        case unexpectedDestinationPermissionsMutation
    }

    private let fileManager = FileManager.default

    func testReplaceItemCreatesDestinationAndAppliesRequestedPermissions() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(rootDirectory)
        }

        let destinationURL = rootDirectory
            .appendingPathComponent("recordings", isDirectory: true)
            .appendingPathComponent("transcripts.sqlite", isDirectory: false)
        let writer = FileManagerAtomicFileWriter(fileManager: fileManager)

        try writer.replaceItem(at: destinationURL, permissions: 0o600) { temporaryURL in
            try Data("fresh".utf8).write(to: temporaryURL)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("fresh".utf8))

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    func testReplaceItemReplacesExistingContents() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(rootDirectory)
        }

        let destinationURL = rootDirectory.appendingPathComponent("transcripts.jsonl", isDirectory: false)
        try Data("old".utf8).write(to: destinationURL)

        let writer = FileManagerAtomicFileWriter(fileManager: fileManager)
        try writer.replaceItem(at: destinationURL, permissions: nil) { temporaryURL in
            try Data("new".utf8).write(to: temporaryURL)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))
    }

    func testReplaceItemReplacingExistingDestinationKeepsRequestedPermissionsWithoutPostRenameMutation() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(rootDirectory)
        }

        let destinationURL = rootDirectory.appendingPathComponent("transcripts.jsonl", isDirectory: false)
        try Data("old".utf8).write(to: destinationURL)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o644)],
            ofItemAtPath: destinationURL.path
        )

        let writer = FileManagerAtomicFileWriter(
            fileManager: fileManager,
            applyAttributes: { fileManager, attributes, path in
                if path == destinationURL.path {
                    throw TestError.unexpectedDestinationPermissionsMutation
                }

                try fileManager.setAttributes(attributes, ofItemAtPath: path)
            }
        )

        try writer.replaceItem(at: destinationURL, permissions: 0o600) { temporaryURL in
            try Data("new".utf8).write(to: temporaryURL)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("new".utf8))

        let attributes = try fileManager.attributesOfItem(atPath: destinationURL.path)
        let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
        XCTAssertEqual(permissions, 0o600)
    }

    func testReplaceItemCleansTemporaryArtifactsOnFailureAndLeavesDestinationUntouched() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(rootDirectory)
        }

        let destinationURL = rootDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        try Data("original".utf8).write(to: destinationURL)

        let writer = FileManagerAtomicFileWriter(fileManager: fileManager)

        do {
            try writer.replaceItem(at: destinationURL, permissions: nil) { temporaryURL in
                try Data("partial".utf8).write(to: temporaryURL)
                throw TestError.expectedFailure
            }
            XCTFail("Expected the write closure failure to be surfaced.")
        } catch {
            XCTAssertEqual(error as? TestError, .expectedFailure)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("original".utf8))

        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.map(\.lastPathComponent).sorted(), ["transcripts.sqlite"])
    }

    func testReplaceItemLeavesDestinationUntouchedWhenApplyingRequestedPermissionsFails() throws {
        let rootDirectory = try makeTemporaryDirectory()
        defer {
            cleanup(rootDirectory)
        }

        let destinationURL = rootDirectory.appendingPathComponent("transcripts.sqlite", isDirectory: false)
        try Data("original".utf8).write(to: destinationURL)

        let writer = FileManagerAtomicFileWriter(
            fileManager: fileManager,
            applyAttributes: { _, _, _ in
                throw TestError.expectedFailure
            }
        )

        do {
            try writer.replaceItem(at: destinationURL, permissions: 0o600) { temporaryURL in
                try Data("partial".utf8).write(to: temporaryURL)
            }
            XCTFail("Expected the permissions failure to be surfaced.")
        } catch {
            XCTAssertEqual(error as? TestError, .expectedFailure)
        }

        XCTAssertEqual(try Data(contentsOf: destinationURL), Data("original".utf8))

        let contents = try fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(contents.map(\.lastPathComponent).sorted(), ["transcripts.sqlite"])
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.standardizedFileURL
    }

    private func cleanup(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }
}
