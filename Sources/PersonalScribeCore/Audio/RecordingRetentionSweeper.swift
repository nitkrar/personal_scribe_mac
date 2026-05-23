import Foundation

public actor RecordingRetentionSweeper {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let recordingsDirectory: @Sendable () throws -> URL
    private let repository: any TranscriptAudioFilenameNullifying
    private let retentionDays: @Sendable () -> Int
    private let now: @Sendable () -> Date
    private let fileManager: FileManager
    private let diagnostics: PersonalScribeLogger
    private let sleep: Sleep
    private var task: Task<Void, Never>?

    public init(
        recordingsDirectory: @escaping @Sendable () throws -> URL = { try AppConfig.recordingsDirectory() },
        repository: any TranscriptAudioFilenameNullifying,
        retentionDays: @escaping @Sendable () -> Int = { AudioRecordingRetentionDaysPreference.resolve() },
        now: @escaping @Sendable () -> Date = Date.init,
        fileManager: FileManager = .default,
        diagnostics: PersonalScribeLogger,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        self.recordingsDirectory = recordingsDirectory
        self.repository = repository
        self.retentionDays = retentionDays
        self.now = now
        self.fileManager = fileManager
        self.diagnostics = diagnostics
        self.sleep = sleep
    }

    deinit {
        task?.cancel()
    }

    public func sweep() async {
        let effectiveRetentionDays = AudioRecordingRetentionDaysPreference.sanitized(retentionDays())
        guard effectiveRetentionDays > 0 else {
            return
        }

        let cutoff = now().addingTimeInterval(-TimeInterval(effectiveRetentionDays) * 86_400)

        do {
            let directory = try recordingsDirectory()
            let staleFiles = try staleAudioFiles(in: directory, olderThan: cutoff)

            var removedFilenames: [String] = []
            var failedRemovals = 0

            for staleFile in staleFiles {
                do {
                    try fileManager.removeItem(at: staleFile)
                    removedFilenames.append(staleFile.lastPathComponent)
                } catch {
                    failedRemovals += 1
                }
            }

            if !removedFilenames.isEmpty {
                try await repository.nullifyAudioFilenames(removedFilenames.sorted())
            }

            diagnostics.info(
                "RecordingRetentionSweeper sweep complete",
                metadata: [
                    "candidates": "\(staleFiles.count)",
                    "deleted": "\(removedFilenames.count)",
                    "failed": "\(failedRemovals)",
                    "retentionDays": "\(effectiveRetentionDays)",
                ]
            )
        } catch {
            diagnostics.error(
                "RecordingRetentionSweeper sweep failed",
                error: error,
                metadata: ["retentionDays": "\(effectiveRetentionDays)"]
            )
        }
    }

    public func start() async {
        guard task == nil else {
            return
        }

        await sweep()
        task = Task { [sleep] in
            while !Task.isCancelled {
                do {
                    try await sleep(.seconds(86_400))
                } catch is CancellationError {
                    return
                } catch {
                    return
                }

                await self.sweep()
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }

    private func staleAudioFiles(in directory: URL, olderThan cutoff: Date) throws -> [URL] {
        guard fileManager.fileExists(atPath: directory.path) else {
            return []
        }

        return try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
            ],
            options: [.skipsHiddenFiles]
        )
        .compactMap { url -> URL? in
            guard url.pathExtension.lowercased() == "wav" else {
                return nil
            }

            let values = try url.resourceValues(forKeys: [
                .contentModificationDateKey,
                .isRegularFileKey,
            ])
            guard values.isRegularFile == true else {
                return nil
            }

            let modificationDate = values.contentModificationDate ?? .distantPast
            return modificationDate < cutoff ? url : nil
        }
    }
}
