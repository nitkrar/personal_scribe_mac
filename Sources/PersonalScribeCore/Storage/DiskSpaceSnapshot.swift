import Foundation

public struct DiskSpaceSnapshot: Sendable, Equatable {
    public let capturedAt: Date
    public let baseDirectory: URL
    public let usedBytesByDirectory: [ManagedDirectory: Int64]
    public let totalUsedBytes: Int64
    public let volumeAvailableBytes: Int64?

    public init(
        capturedAt: Date,
        baseDirectory: URL,
        usedBytesByDirectory: [ManagedDirectory: Int64],
        volumeAvailableBytes: Int64?
    ) {
        self.capturedAt = capturedAt
        self.baseDirectory = baseDirectory.standardizedFileURL
        self.usedBytesByDirectory = usedBytesByDirectory
        self.totalUsedBytes = usedBytesByDirectory.values.reduce(0, +)
        self.volumeAvailableBytes = volumeAvailableBytes
    }

    public static func capture(
        from storageLocator: any StorageLocator,
        fileManager: FileManager = .default,
        capturedAt: Date = Date()
    ) throws -> DiskSpaceSnapshot {
        let baseDirectory = storageLocator.baseDirectory.standardizedFileURL
        var usedBytesByDirectory: [ManagedDirectory: Int64] = [:]

        for directory in ManagedDirectory.allCases {
            usedBytesByDirectory[directory] = try ManagedDirectoryByteCounter.totalBytes(
                in: storageLocator.url(for: directory),
                fileManager: fileManager
            )
        }

        let volumeURL = ManagedDirectoryByteCounter.existingAncestor(for: baseDirectory, fileManager: fileManager)
        let resourceValues = try volumeURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])

        return DiskSpaceSnapshot(
            capturedAt: capturedAt,
            baseDirectory: baseDirectory,
            usedBytesByDirectory: usedBytesByDirectory,
            volumeAvailableBytes: resourceValues.volumeAvailableCapacityForImportantUsage
        )
    }
}

enum ManagedDirectoryByteCounter {
    static func totalBytes(in directory: URL, fileManager: FileManager) throws -> Int64 {
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory)
        guard exists else {
            return 0
        }

        let resourceKeys: Set<URLResourceKey> = [
            .isDirectoryKey,
            .isRegularFileKey,
            .totalFileAllocatedSizeKey,
            .fileAllocatedSizeKey,
            .totalFileSizeKey,
            .fileSizeKey,
        ]
        let children = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(resourceKeys),
            options: []
        )

        return try children.reduce(into: Int64.zero) { partialResult, child in
            let resourceValues = try child.resourceValues(forKeys: resourceKeys)
            if resourceValues.isDirectory == true {
                partialResult += try totalBytes(in: child, fileManager: fileManager)
            } else if resourceValues.isRegularFile == true {
                let childBytes =
                    resourceValues.totalFileAllocatedSize ??
                    resourceValues.fileAllocatedSize ??
                    resourceValues.totalFileSize ??
                    resourceValues.fileSize ??
                    0
                partialResult += Int64(childBytes)
            }
        }
    }

    static func existingAncestor(for url: URL, fileManager: FileManager) -> URL {
        var candidate = url.standardizedFileURL

        while !fileManager.fileExists(atPath: candidate.path) {
            let parent = candidate.deletingLastPathComponent().standardizedFileURL
            if parent == candidate {
                return candidate
            }
            candidate = parent
        }

        return candidate
    }
}
