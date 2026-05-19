@preconcurrency import AVFoundation
import Foundation

public protocol FileSourceAudioStreaming: Sendable {
    func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error>
}

public enum FileSourceAudioError: Error, @unchecked Sendable {
    case fileMissing(URL)
    case unsupportedFormat(URL)
    case conversionFailed(underlying: any Error)
}

public struct FileSourceAudioStream: FileSourceAudioStreaming, Sendable {
    private static let targetFramesPerChunk = 1_600

    public init() {}

    public func stream(from url: URL) -> AsyncThrowingStream<PCMBuffer, Error> {
        let standardizedURL = url.standardizedFileURL

        return AsyncThrowingStream { continuation in
            let producerTask = Task {
                do {
                    try await streamFile(at: standardizedURL, continuation: continuation)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                producerTask.cancel()
            }
        }
    }

    private func streamFile(
        at url: URL,
        continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation
    ) async throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            throw FileSourceAudioError.fileMissing(url)
        }

        let audioFile: AVAudioFile
        do {
            audioFile = try AVAudioFile(forReading: url)
        } catch {
            throw FileSourceAudioError.unsupportedFormat(url)
        }

        let sourceFormat = audioFile.processingFormat
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0 else {
            throw FileSourceAudioError.unsupportedFormat(url)
        }

        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: AppConfig.sampleRate,
            channels: AVAudioChannelCount(AppConfig.channelCount),
            interleaved: false
        ) else {
            throw FileSourceAudioError.unsupportedFormat(url)
        }

        let sourceFramesPerRead = max(
            1,
            Int(
                ceil(
                    Double(Self.targetFramesPerChunk) * sourceFormat.sampleRate / AppConfig.sampleRate
                )
            )
        )
        var pendingSamples: [Float] = []
        pendingSamples.reserveCapacity(Self.targetFramesPerChunk * 2)

        while !Task.isCancelled {
            if audioFile.framePosition >= audioFile.length {
                break
            }

            guard let inputBuffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: AVAudioFrameCount(sourceFramesPerRead)
            ) else {
                throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
            }

            do {
                try audioFile.read(
                    into: inputBuffer,
                    frameCount: AVAudioFrameCount(sourceFramesPerRead)
                )
            } catch {
                throw FileSourceAudioError.conversionFailed(underlying: error)
            }

            if inputBuffer.frameLength == 0 {
                break
            }

            let monoSamples = try extractMonoSamples(
                from: inputBuffer,
                format: sourceFormat
            )
            let samples = try resampleIfNeeded(
                monoSamples,
                inputSampleRate: sourceFormat.sampleRate,
                targetFormat: targetFormat
            )

            pendingSamples.append(contentsOf: samples)

            var emittedCount = 0
            while pendingSamples.count - emittedCount >= Self.targetFramesPerChunk {
                let chunk = Array(
                    pendingSamples[emittedCount..<(emittedCount + Self.targetFramesPerChunk)]
                )
                emittedCount += Self.targetFramesPerChunk
                continuation.yield(
                    try PCMBuffer(
                        samples: chunk,
                        timestamp: ContinuousClock().now
                    )
                )
                await Task.yield()
                if Task.isCancelled {
                    continuation.finish()
                    return
                }
            }

            if emittedCount > 0 {
                pendingSamples.removeFirst(emittedCount)
            }
        }

        if !Task.isCancelled, !pendingSamples.isEmpty {
            continuation.yield(
                try PCMBuffer(
                    samples: pendingSamples,
                    timestamp: ContinuousClock().now
                )
            )
        }

        continuation.finish()
    }

    private func extractMonoSamples(
        from inputBuffer: AVAudioPCMBuffer,
        format: AVAudioFormat
    ) throws -> [Float] {
        let frameCount = Int(inputBuffer.frameLength)
        let channelCount = Int(format.channelCount)
        guard frameCount > 0, channelCount > 0 else {
            return []
        }

        switch format.commonFormat {
        case .pcmFormatFloat32:
            guard let channelData = inputBuffer.floatChannelData else {
                throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
            }

            var monoSamples = Array(repeating: Float.zero, count: frameCount)
            for channelIndex in 0..<channelCount {
                let source = channelData[channelIndex]
                for frame in 0..<frameCount {
                    monoSamples[frame] += source[frame]
                }
            }

            if channelCount > 1 {
                let scale = Float(channelCount)
                for frame in 0..<frameCount {
                    monoSamples[frame] /= scale
                }
            }

            return monoSamples

        case .pcmFormatInt16:
            guard let channelData = inputBuffer.int16ChannelData else {
                throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
            }

            var monoSamples = Array(repeating: Float.zero, count: frameCount)
            for channelIndex in 0..<channelCount {
                let source = channelData[channelIndex]
                for frame in 0..<frameCount {
                    monoSamples[frame] += Float(source[frame]) / Float(Int16.max)
                }
            }

            if channelCount > 1 {
                let scale = Float(channelCount)
                for frame in 0..<frameCount {
                    monoSamples[frame] /= scale
                }
            }

            return monoSamples

        case .pcmFormatInt32:
            guard let channelData = inputBuffer.int32ChannelData else {
                throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
            }

            var monoSamples = Array(repeating: Float.zero, count: frameCount)
            for channelIndex in 0..<channelCount {
                let source = channelData[channelIndex]
                for frame in 0..<frameCount {
                    monoSamples[frame] += Float(source[frame]) / Float(Int32.max)
                }
            }

            if channelCount > 1 {
                let scale = Float(channelCount)
                for frame in 0..<frameCount {
                    monoSamples[frame] /= scale
                }
            }

            return monoSamples

        default:
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }
    }

    private func resampleIfNeeded(
        _ monoSamples: [Float],
        inputSampleRate: Double,
        targetFormat: AVAudioFormat
    ) throws -> [Float] {
        if inputSampleRate == AppConfig.sampleRate {
            return monoSamples
        }

        guard let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: inputSampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }

        let inputCapacity = AVAudioFrameCount(monoSamples.count)
        guard let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFormat,
            frameCapacity: inputCapacity
        ) else {
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }
        inputBuffer.frameLength = inputCapacity

        guard let inputChannel = inputBuffer.floatChannelData?[0] else {
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }
        monoSamples.withUnsafeBufferPointer { source in
            if let baseAddress = source.baseAddress {
                inputChannel.update(from: baseAddress, count: monoSamples.count)
            }
        }

        let outputCapacity = max(
            1,
            AVAudioFrameCount(
                ceil(Double(inputCapacity) * AppConfig.sampleRate / inputSampleRate) + 64
            )
        )

        guard let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: outputCapacity
        ) else {
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }

        var conversionError: NSError?
        let feedState = InputFeedState()
        let status = converter.convert(to: outputBuffer, error: &conversionError) { _, outStatus in
            if feedState.didFeedInput {
                outStatus.pointee = .endOfStream
                return nil
            }

            feedState.didFeedInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let conversionError {
            throw FileSourceAudioError.conversionFailed(underlying: conversionError)
        }

        switch status {
        case .haveData, .inputRanDry, .endOfStream:
            break
        case .error:
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        @unknown default:
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }

        guard let channelData = outputBuffer.floatChannelData?[0] else {
            throw FileSourceAudioError.conversionFailed(underlying: PersonalScribeError.resampleFailure)
        }

        return Array(
            UnsafeBufferPointer(
                start: channelData,
                count: Int(outputBuffer.frameLength)
            )
        )
    }
}

private final class InputFeedState: @unchecked Sendable {
    var didFeedInput = false
}
