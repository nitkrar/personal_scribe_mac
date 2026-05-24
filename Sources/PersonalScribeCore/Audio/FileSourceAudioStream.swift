@preconcurrency import AVFoundation
import Foundation

public protocol FileSourceAudioStreaming: Sendable {
    func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error>
}

public enum FileSourceAudioError: Error, Sendable, Equatable {
    case fileMissing(URL)
    case unsupportedFormat(URL)
    case conversionFailed(underlying: String)
}

private final class FileSourceAudioStreamFeedFlag: @unchecked Sendable {
    var didFeed = false
}

private final class FileSourceAudioStreamCancellationState: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        let value = cancelled
        lock.unlock()
        return value
    }
}

public struct FileSourceAudioStream: FileSourceAudioStreaming, Sendable {
    private let chunkFrameCount: AVAudioFrameCount

    public init(
        chunkFrameCount: AVAudioFrameCount = 1_600
    ) {
        self.chunkFrameCount = chunkFrameCount
    }

    public func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error> {
        AsyncThrowingStream { continuation in
            let cancellationState = FileSourceAudioStreamCancellationState()
            let task = Task(priority: .userInitiated) {
                do {
                    try await produceStream(
                        from: url.standardizedFileURL,
                        continuation: continuation,
                        cancellationState: cancellationState
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                cancellationState.cancel()
                task.cancel()
            }
        }
    }

    private func produceStream(
        from url: URL,
        continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation,
        cancellationState: FileSourceAudioStreamCancellationState
    ) async throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw FileSourceAudioError.fileMissing(url)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw FileSourceAudioError.unsupportedFormat(url)
        }

        let sourceFormat = audioFile.processingFormat
        guard
            sourceFormat.sampleRate > 0,
            sourceFormat.channelCount > 0,
            let decodeFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: sourceFormat.sampleRate,
                channels: sourceFormat.channelCount,
                interleaved: false
            ),
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: AppConfig.sampleRate,
                channels: AVAudioChannelCount(AppConfig.channelCount),
                interleaved: false
            )
        else {
            throw FileSourceAudioError.unsupportedFormat(url)
        }

        let requiresConversion =
            decodeFormat.sampleRate != AppConfig.sampleRate ||
            decodeFormat.channelCount != AVAudioChannelCount(AppConfig.channelCount)

        let inputFrameCapacity = max(chunkFrameCount, AVAudioFrameCount(4_096))
        let baseTimestamp = ContinuousClock().now
        var emittedFrameCount = 0
        var pendingSamples: [Float] = []
        pendingSamples.reserveCapacity(Int(chunkFrameCount) * 2)

        while audioFile.framePosition < audioFile.length {
            try Task.checkCancellation()
            if cancellationState.isCancelled {
                throw CancellationError()
            }

            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: decodeFormat,
                frameCapacity: inputFrameCapacity
            ) else {
                throw FileSourceAudioError.conversionFailed(
                    underlying: "Failed to allocate input AVAudioPCMBuffer"
                )
            }

            do {
                try audioFile.read(into: inputBuffer)
            } catch {
                throw FileSourceAudioError.conversionFailed(
                    underlying: String(describing: error)
                )
            }
            if inputBuffer.frameLength == 0 {
                break
            }
            pendingSamples.append(
                contentsOf: try convertSamples(
                    in: inputBuffer,
                    requiresConversion: requiresConversion,
                    outputFormat: outputFormat
                )
            )

            while pendingSamples.count >= Int(chunkFrameCount) {
                let chunk = Array(pendingSamples.prefix(Int(chunkFrameCount)))
                pendingSamples.removeFirst(Int(chunkFrameCount))
                try await emitChunk(
                    chunk,
                    continuation: continuation,
                    baseTimestamp: baseTimestamp,
                    emittedFrameCount: &emittedFrameCount
                )
            }
        }

        if !pendingSamples.isEmpty {
            try await emitChunk(
                pendingSamples,
                continuation: continuation,
                baseTimestamp: baseTimestamp,
                emittedFrameCount: &emittedFrameCount
            )
        }
    }

    private func convertSamples(
        in inputBuffer: AVAudioPCMBuffer,
        requiresConversion: Bool,
        outputFormat: AVAudioFormat
    ) throws -> [Float] {
        if !requiresConversion {
            return try extractSamples(from: inputBuffer)
        }

        guard let converter = AVAudioConverter(from: inputBuffer.format, to: outputFormat) else {
            throw FileSourceAudioError.conversionFailed(
                underlying: "Failed to create AVAudioConverter"
            )
        }

        let outputCapacity = AVAudioFrameCount(
            ceil(Double(inputBuffer.frameLength) * AppConfig.sampleRate / inputBuffer.format.sampleRate)
        ) + 32
        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: outputCapacity
        ) else {
            throw FileSourceAudioError.conversionFailed(
                underlying: "Failed to allocate output AVAudioPCMBuffer"
            )
        }

        var conversionError: NSError?
        let feedFlag = FileSourceAudioStreamFeedFlag()
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if feedFlag.didFeed {
                outStatus.pointee = .endOfStream
                return nil
            }
            feedFlag.didFeed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw FileSourceAudioError.conversionFailed(
                underlying: String(describing: conversionError)
            )
        }
        if status == .error {
            throw FileSourceAudioError.conversionFailed(
                underlying: "AVAudioConverter.convert returned .error"
            )
        }

        return try extractSamples(from: outputBuffer)
    }

    private func extractSamples(from buffer: AVAudioPCMBuffer) throws -> [Float] {
        guard let channelData = buffer.floatChannelData?[0] else {
            throw FileSourceAudioError.conversionFailed(
                underlying: "Failed to read converted channel data"
            )
        }

        return Array(
            UnsafeBufferPointer(
                start: channelData,
                count: Int(buffer.frameLength)
            )
        )
    }

    private func emitChunk(
        _ samples: [Float],
        continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation,
        baseTimestamp: ContinuousClock.Instant,
        emittedFrameCount: inout Int
    ) async throws {
        let timestamp = baseTimestamp.advanced(
            by: .seconds(Double(emittedFrameCount) / AppConfig.sampleRate)
        )
        let buffer = try PCMBuffer(
            samples: samples,
            timestamp: timestamp
        )
        emittedFrameCount += buffer.frameCount

        if case .terminated = continuation.yield(buffer) {
            throw CancellationError()
        }

        await Task.yield()
    }
}
