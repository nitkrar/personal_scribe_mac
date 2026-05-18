@preconcurrency import whisper
import Foundation
import PersonalScribeCore

protocol WhisperCppManaging: Sendable {
    func loadModel(from modelFileURL: URL) async throws
    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> WhisperCppManagerResult
    func cleanup() async
}

protocol WhisperCppDownloading: Sendable {
    func download(
        from remoteURL: URL,
        to temporaryURL: URL,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws
}

protocol WhisperCppLibrary: Sendable {
    func createContext(modelPath: String) throws -> OpaquePointer
    func freeContext(_ context: OpaquePointer)
    func transcribe(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> String
}

struct WhisperCppManagerResult: Sendable, Equatable {
    let text: String
}

public actor WhisperCppTranscriberAdapter: Transcriber {
    public nonisolated let capabilities = TranscriberCapabilities()

    private let descriptor: ModelDescriptor
    private let storageLocator: any StorageLocator
    private let manager: any WhisperCppManaging
    private let downloader: any WhisperCppDownloading
    private nonisolated let progressBroadcaster = FluidAudioDownloadProgressBroadcaster()
    private let fileManager: FileManager
    private var hasPreparedModel = false
    private var prepareTask: Task<Void, Error>?

    public init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator = AppConfig.liveStorageLocator()
    ) {
        self.init(
            descriptor: descriptor,
            storageLocator: storageLocator,
            manager: LiveWhisperCppManager(),
            downloader: LiveWhisperCppDownloader()
        )
    }

    init(
        descriptor: ModelDescriptor,
        storageLocator: any StorageLocator,
        manager: any WhisperCppManaging,
        downloader: any WhisperCppDownloading,
        fileManager: FileManager = .default
    ) {
        self.descriptor = descriptor
        self.storageLocator = storageLocator
        self.manager = manager
        self.downloader = downloader
        self.fileManager = fileManager
    }

    public func prepare() async throws {
        if hasPreparedModel {
            return
        }

        if let prepareTask {
            return try await prepareTask.value
        }

        let task = Task {
            try await self.performPrepare()
        }
        prepareTask = task

        do {
            try await task.value
            hasPreparedModel = true
            prepareTask = nil
        } catch {
            prepareTask = nil
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public func downloadIfNeeded() async throws {
        do {
            try await performDownloadIfNeeded(emitFinished: true)
        } catch {
            progressBroadcaster.emit(.idle)
            throw error
        }
    }

    public nonisolated func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
        progressBroadcaster.stream()
    }

    public func cleanup() async {
        let inFlightPrepare = prepareTask
        prepareTask = nil
        hasPreparedModel = false
        inFlightPrepare?.cancel()
        await manager.cleanup()
        progressBroadcaster.emit(.idle)
    }

    public func transcribe(
        _ audio: PCMBuffer,
        languageHint: String?
    ) async throws -> TranscriptionResult {
        try await prepare()

        let startedAt = ContinuousClock.now

        do {
            let result = try await manager.transcribe(
                audioSamples: audio.samples,
                languageHint: languageHint
            )
            let measuredTotalDuration = startedAt.duration(to: ContinuousClock.now)
            return makeTranscriptionResult(
                from: result,
                audioDuration: audio.duration,
                processingDuration: measuredTotalDuration
            )
        } catch {
            throw PersonalScribeError.transcriptionFailure
        }
    }
}

private extension WhisperCppTranscriberAdapter {
    func performPrepare() async throws {
        let modelFileURL = try modelFileURL()
        try await performDownloadIfNeeded(emitFinished: false)
        progressBroadcaster.emit(.loading)

        do {
            try await manager.loadModel(from: modelFileURL)
            progressBroadcaster.emit(.finished)
        } catch {
            await manager.cleanup()
            throw PersonalScribeError.modelLoadFailure
        }
    }

    func performDownloadIfNeeded(emitFinished: Bool) async throws {
        try storageLocator.ensureDirectoriesExist()
        let modelDirectory = try modelDirectory()
        let modelFileURL = try modelFileURL()
        let temporaryFileURL = temporaryModelFileURL(for: modelFileURL)

        guard
            !WhisperCppArtifactFilesystem.modelArtifactsAreValid(
                in: modelDirectory,
                descriptor: descriptor,
                fileManager: fileManager
            )
        else {
            if emitFinished {
                progressBroadcaster.emit(.finished)
            }
            return
        }

        try fileManager.createDirectory(
            at: modelDirectory,
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: modelFileURL.path) {
            try? fileManager.removeItem(at: modelFileURL)
        }
        if fileManager.fileExists(atPath: temporaryFileURL.path) {
            try? fileManager.removeItem(at: temporaryFileURL)
        }

        let remoteURL = try remoteModelURL()
        let broadcaster = progressBroadcaster
        progressBroadcaster.emit(.downloading)

        do {
            try await downloader.download(
                from: remoteURL,
                to: temporaryFileURL,
                progressHandler: { snapshot in
                    broadcaster.emit(snapshot)
                }
            )
            try moveDownloadedFileIntoPlace(
                temporaryFileURL: temporaryFileURL,
                modelFileURL: modelFileURL
            )
        } catch {
            try? cleanupPartialDownload(
                temporaryFileURL: temporaryFileURL,
                modelFileURL: modelFileURL
            )
            throw PersonalScribeError.modelLoadFailure
        }

        if emitFinished {
            progressBroadcaster.emit(.finished)
        }
    }

    func moveDownloadedFileIntoPlace(
        temporaryFileURL: URL,
        modelFileURL: URL
    ) throws {
        if fileManager.fileExists(atPath: modelFileURL.path) {
            _ = try fileManager.replaceItemAt(
                modelFileURL,
                withItemAt: temporaryFileURL
            )
            return
        }

        try fileManager.moveItem(at: temporaryFileURL, to: modelFileURL)
    }

    func cleanupPartialDownload(
        temporaryFileURL: URL,
        modelFileURL: URL
    ) throws {
        if fileManager.fileExists(atPath: temporaryFileURL.path) {
            try fileManager.removeItem(at: temporaryFileURL)
        }

        if fileManager.fileExists(atPath: modelFileURL.path) {
            try fileManager.removeItem(at: modelFileURL)
        }
    }

    func modelDirectory() throws -> URL {
        try storageLocator.ensureDirectoriesExist()
        let directory = storageLocator
            .url(for: .models)
            .appendingPathComponent(descriptor.repoFolderName, isDirectory: true)
            .standardizedFileURL
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }

    func modelFileURL() throws -> URL {
        try modelDirectory()
            .appendingPathComponent(requiredModelFilename(), isDirectory: false)
            .standardizedFileURL
    }

    func temporaryModelFileURL(for modelFileURL: URL) -> URL {
        modelFileURL
            .appendingPathExtension("download")
            .standardizedFileURL
    }

    func remoteModelURL() throws -> URL {
        descriptor.resolveURL(for: try requiredModelFilename())
    }

    func requiredModelFilename() throws -> String {
        guard descriptor.requiredRelativePaths.count == 1 else {
            throw PersonalScribeError.modelLoadFailure
        }

        let filename = descriptor.requiredRelativePaths[0]
        guard
            !filename.isEmpty,
            !filename.contains("/"),
            descriptor.tokenizerSource == nil,
            descriptor.auxiliaryRepoFolderNames.isEmpty
        else {
            throw PersonalScribeError.modelLoadFailure
        }

        return filename
    }

    func makeTranscriptionResult(
        from result: WhisperCppManagerResult,
        audioDuration: Duration,
        processingDuration: Duration
    ) -> TranscriptionResult {
        TranscriptionResult(
            text: result.text,
            audioDuration: audioDuration,
            processingDuration: processingDuration
        )
    }
}

private enum WhisperCppArtifactFilesystem {
    static func modelArtifactsAreValid(
        in directory: URL,
        descriptor: ModelDescriptor,
        fileManager: FileManager
    ) -> Bool {
        let requiredPaths = descriptor.requiredRelativePaths.map {
            directory.appendingPathComponent($0, isDirectory: false)
        }

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

internal final class LiveWhisperCppDownloader: WhisperCppDownloading, @unchecked Sendable {
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func download(
        from remoteURL: URL,
        to temporaryURL: URL,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws {
        try fileManager.createDirectory(
            at: temporaryURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if fileManager.fileExists(atPath: temporaryURL.path) {
            try fileManager.removeItem(at: temporaryURL)
        }
        guard fileManager.createFile(atPath: temporaryURL.path, contents: nil) else {
            throw URLError(.cannotCreateFile)
        }

        let fileHandle = try FileHandle(forWritingTo: temporaryURL)
        let delegate = WhisperCppStreamingDownloadDelegate(
            fileHandle: fileHandle,
            progressHandler: progressHandler
        )
        let delegateQueue = OperationQueue()
        delegateQueue.maxConcurrentOperationCount = 1
        let session = URLSession(
            configuration: .ephemeral,
            delegate: delegate,
            delegateQueue: delegateQueue
        )
        defer {
            session.finishTasksAndInvalidate()
        }

        do {
            try await delegate.download(with: session, from: remoteURL)
        } catch {
            try? fileHandle.close()
            throw error
        }
    }
}

private final class WhisperCppStreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let fileHandle: FileHandle
    private let progressHandler: @Sendable (ModelDownloadProgress) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Error>?
    private var hasCompleted = false
    private var bytesReceived: Int64 = 0
    private var expectedBytes: Int64?

    init(
        fileHandle: FileHandle,
        progressHandler: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) {
        self.fileHandle = fileHandle
        self.progressHandler = progressHandler
    }

    func download(with session: URLSession, from remoteURL: URL) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.withLock {
                self.continuation = continuation
            }

            let task = session.dataTask(with: remoteURL)
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            complete(with: URLError(.badServerResponse))
            completionHandler(.cancel)
            return
        }

        let responseLength = response.expectedContentLength
        expectedBytes = responseLength > 0 ? responseLength : nil
        progressHandler(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 0,
            receivedBytes: 0,
            expectedBytes: expectedBytes
        ))
        completionHandler(.allow)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        guard !isCompleted else {
            return
        }

        do {
            try fileHandle.write(contentsOf: data)
            bytesReceived += Int64(data.count)
            let fractionCompleted: Double
            if let expectedBytes, expectedBytes > 0 {
                fractionCompleted = min(max(Double(bytesReceived) / Double(expectedBytes), 0), 1)
            } else {
                fractionCompleted = 0
            }

            progressHandler(ModelDownloadProgress(
                phase: .downloading,
                fractionCompleted: fractionCompleted,
                receivedBytes: bytesReceived,
                expectedBytes: expectedBytes
            ))
        } catch {
            complete(with: error)
            dataTask.cancel()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        try? fileHandle.close()

        if let error {
            complete(with: error)
            return
        }

        progressHandler(ModelDownloadProgress(
            phase: .downloading,
            fractionCompleted: 1,
            receivedBytes: bytesReceived,
            expectedBytes: expectedBytes
        ))
        complete()
    }

    private var isCompleted: Bool {
        lock.withLock {
            hasCompleted
        }
    }

    private func complete() {
        complete(with: nil)
    }

    private func complete(with error: Error?) {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard !hasCompleted else {
                return nil
            }

            hasCompleted = true
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }

        guard let continuation else {
            return
        }

        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }
}

internal final class LiveWhisperCppManager: WhisperCppManaging, @unchecked Sendable {
    private enum RuntimeError: Error {
        case modelNotLoaded
    }

    private let queue = DispatchQueue(label: "personal_scribe.whispercpp.runtime")
    private let library: any WhisperCppLibrary
    private var context: OpaquePointer?
    private var loadedModelPath: String?

    init(library: any WhisperCppLibrary = LiveWhisperCppLibrary()) {
        self.library = library
    }

    func loadModel(from modelFileURL: URL) async throws {
        let standardizedPath = modelFileURL.standardizedFileURL.path
        try await enqueue {
            if self.context != nil, self.loadedModelPath == standardizedPath {
                return
            }

            if let context = self.context {
                self.library.freeContext(context)
                self.context = nil
                self.loadedModelPath = nil
            }

            let context = try self.library.createContext(modelPath: standardizedPath)
            self.context = context
            self.loadedModelPath = standardizedPath
        }
    }

    func transcribe(
        audioSamples: [Float],
        languageHint: String?
    ) async throws -> WhisperCppManagerResult {
        let nThreads = Self.defaultThreadCount()
        return try await enqueue {
            guard let context = self.context else {
                throw RuntimeError.modelNotLoaded
            }

            let text = try self.library.transcribe(
                context: context,
                audioSamples: audioSamples,
                nThreads: nThreads,
                languageHint: languageHint
            )
            return WhisperCppManagerResult(text: text)
        }
    }

    func cleanup() async {
        try? await enqueue {
            if let context = self.context {
                self.library.freeContext(context)
            }
            self.context = nil
            self.loadedModelPath = nil
        }
    }

    private func enqueue<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    continuation.resume(returning: try work())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func defaultThreadCount() -> Int32 {
        let availableProcessors = ProcessInfo.processInfo.activeProcessorCount
        return Int32(max(1, min(8, availableProcessors - 2)))
    }
}

private struct LiveWhisperCppLibrary: WhisperCppLibrary {
    private enum LibraryError: Error {
        case contextInitFailed
        case transcriptionFailed
    }

    func createContext(modelPath: String) throws -> OpaquePointer {
        var params = whisper_context_default_params()
        params.use_gpu = true
        params.flash_attn = true

        guard let context = whisper_init_from_file_with_params(modelPath, params) else {
            throw LibraryError.contextInitFailed
        }

        return context
    }

    func freeContext(_ context: OpaquePointer) {
        whisper_free(context)
    }

    func transcribe(
        context: OpaquePointer,
        audioSamples: [Float],
        nThreads: Int32,
        languageHint: String?
    ) throws -> String {
        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_special = false
        params.print_progress = false
        params.print_realtime = false
        params.print_timestamps = false
        params.translate = false
        params.no_context = true
        params.single_segment = false
        // Do NOT set params.detect_language = true. Upstream semantics
        // are "exit after automatically detecting language" (per
        // whisper.cpp's CLI --detect-language help). With language="auto"
        // below, that short-circuits the decoder and returns zero
        // segments — symptom: empty transcripts with ~80ms processing
        // time on multi-second audio.
        params.suppress_blank = true
        params.suppress_nst = true
        params.n_threads = nThreads
        params.offset_ms = 0
        params.duration_ms = 0

        let resolvedLanguage = languageHint ?? "auto"
        let resultCode = resolvedLanguage.withCString { languageCString -> Int32 in
            params.language = languageCString
            whisper_reset_timings(context)
            return audioSamples.withUnsafeBufferPointer { samples in
                whisper_full(context, params, samples.baseAddress, Int32(samples.count))
            }
        }

        guard resultCode == 0 else {
            throw LibraryError.transcriptionFailed
        }

        var text = ""
        let segmentCount = Int(whisper_full_n_segments(context))
        for index in 0..<segmentCount {
            if let segmentText = whisper_full_get_segment_text(context, Int32(index)) {
                text += String(cString: segmentText)
            }
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
