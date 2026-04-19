import Foundation

public struct TranscriptEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public let timestamp: Date
    public let text: String
    public let audioDuration: TimeInterval
    public let processingDuration: TimeInterval

    public init(
        id: UUID,
        timestamp: Date,
        text: String,
        audioDuration: TimeInterval,
        processingDuration: TimeInterval
    ) {
        self.id = id
        self.timestamp = timestamp
        self.text = text
        self.audioDuration = audioDuration
        self.processingDuration = processingDuration
    }
}

public actor TranscriptStoreJSONL {
    private let fileURL: URL
    private let fileHandle: FileHandle
    private var ring: RingBuffer<TranscriptEntry>

    public init(recordingsDirectory: URL, ringCapacity: Int = 500) throws {
        let storageLocator = FixedBaseDirectoryStorageLocator(
            baseDirectory: recordingsDirectory.deletingLastPathComponent(),
            managedDirectoryOverrides: [.recordings: recordingsDirectory]
        )
        try self.init(storageLocator: storageLocator, ringCapacity: ringCapacity)
    }

    init(storageLocator: any StorageLocator, ringCapacity: Int = 500) throws {
        let normalizedCapacity = max(0, ringCapacity)
        let fileManager = FileManager.default
        let logger = SeshatLogger(category: SeshatLogCategory.app)
        let recordingsDirectory = storageLocator.url(for: .recordings)
        let transcriptsFile = recordingsDirectory
            .appendingPathComponent("transcripts.jsonl", isDirectory: false)
            .standardizedFileURL

        try fileManager.createDirectory(at: recordingsDirectory, withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: transcriptsFile.path) {
            guard fileManager.createFile(
                atPath: transcriptsFile.path,
                contents: nil,
                attributes: [.posixPermissions: NSNumber(value: 0o600)]
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }
        } else {
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: transcriptsFile.path
            )
        }

        var ring = RingBuffer<TranscriptEntry>(capacity: normalizedCapacity)
        for entry in try Self.loadPersistedEntries(from: transcriptsFile, ringCapacity: normalizedCapacity, logger: logger) {
            ring.append(entry)
        }

        self.fileURL = transcriptsFile
        self.fileHandle = try FileHandle(forWritingTo: transcriptsFile)
        self.ring = ring
    }

    deinit {
        try? fileHandle.close()
    }

    public func append(_ entry: TranscriptEntry) async throws {
        var data = try makeEncoder().encode(entry)
        data.append(0x0A)

        _ = try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
        try fileHandle.synchronize()

        ring.append(entry)
    }

    public func recent(limit: Int) async -> [TranscriptEntry] {
        ring.mostRecent(limit: limit)
    }

    public func count() async -> Int {
        ring.count
    }

    static func loadAllPersistedEntries(
        from fileURL: URL,
        logger: SeshatLogger,
        onCorruptLine: ((String) -> Void)? = nil
    ) throws -> [TranscriptEntry] {
        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return []
        }

        let decoder = makeDecoder()
        var entries: [TranscriptEntry] = []

        for line in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            let lineData = Data(line)

            do {
                let entry = try decoder.decode(TranscriptEntry.self, from: lineData)
                entries.append(entry)
            } catch {
                let renderedLine = String(decoding: lineData, as: UTF8.self)
                logger.error(
                    "Skipping corrupt transcript line: \(renderedLine)",
                    error: error
                )
                onCorruptLine?(renderedLine)
            }
        }

        return entries
    }

    private static func loadPersistedEntries(
        from fileURL: URL,
        ringCapacity: Int,
        logger: SeshatLogger
    ) throws -> [TranscriptEntry] {
        guard ringCapacity > 0 else {
            return []
        }

        return Array(
            try loadAllPersistedEntries(from: fileURL, logger: logger)
                .suffix(ringCapacity)
        )
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct RingBuffer<Element> {
    private let capacity: Int
    private var storage: [Element?]
    private(set) var count = 0
    private var head = 0

    init(capacity: Int) {
        self.capacity = max(0, capacity)
        self.storage = Array(repeating: nil, count: max(1, capacity))
    }

    mutating func append(_ element: Element) {
        guard capacity > 0 else {
            return
        }

        if count < capacity {
            storage[(head + count) % capacity] = element
            count += 1
            return
        }

        storage[head] = element
        head = (head + 1) % capacity
    }

    func mostRecent(limit: Int) -> [Element] {
        guard capacity > 0, count > 0, limit > 0 else {
            return []
        }

        let cappedLimit = min(limit, count)
        return (0..<cappedLimit).compactMap { offset in
            element(atLogicalIndex: count - 1 - offset)
        }
    }

    private func element(atLogicalIndex index: Int) -> Element? {
        guard capacity > 0, index >= 0, index < count else {
            return nil
        }

        return storage[(head + index) % capacity]
    }
}
