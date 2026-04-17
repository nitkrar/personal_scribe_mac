import AVFoundation
import Foundation
import SeshatCore

/// Internal actor that converts captured mono `[Float]` samples into the shared
/// `PCMBuffer` wire format (16 kHz mono Float32). Keeps AVFoundation-only types
/// inside `SeshatAudio` and hands back `Sendable` values.
internal actor AudioResampler {
    internal init(
        inputSampleRate: Double,
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio)
    ) throws {
        self.customResampleImpl = nil
        self.logger = logger
        self.inputSampleRate = inputSampleRate
    }

    internal init(
        resampleImpl: @escaping @Sendable ([Float], ContinuousClock.Instant) throws -> PCMBuffer
    ) {
        self.customResampleImpl = resampleImpl
        self.logger = SeshatLogger(category: SeshatLogCategory.audio)
        self.inputSampleRate = SeshatConfig.sampleRate
    }

    internal func resample(
        monoSamples: [Float],
        timestamp: ContinuousClock.Instant
    ) throws -> PCMBuffer {
        if let customResampleImpl {
            return try customResampleImpl(monoSamples, timestamp)
        }
        return try performResample(monoSamples: monoSamples, timestamp: timestamp)
    }

    private func performResample(
        monoSamples: [Float],
        timestamp: ContinuousClock.Instant
    ) throws -> PCMBuffer {
        // Fast path: input already at target rate — no conversion needed.
        if inputSampleRate == SeshatConfig.sampleRate {
            return try PCMBuffer(
                samples: monoSamples,
                sampleRate: SeshatConfig.sampleRate,
                channelCount: SeshatConfig.channelCount,
                timestamp: timestamp
            )
        }

        guard
            let inputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: inputSampleRate,
                channels: 1,
                interleaved: false
            ),
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: SeshatConfig.sampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat)
        else {
            logger.error("Failed to create AVAudioConverter for \(inputSampleRate)Hz -> \(SeshatConfig.sampleRate)Hz")
            throw SeshatError.resampleFailure
        }

        let inputCapacity = AVAudioFrameCount(monoSamples.count)
        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: inputCapacity) else {
            logger.error("Failed to allocate input AVAudioPCMBuffer")
            throw SeshatError.resampleFailure
        }
        inputBuffer.frameLength = inputCapacity
        guard let inputChannel = inputBuffer.floatChannelData?[0] else {
            logger.error("Failed to access input channel data")
            throw SeshatError.resampleFailure
        }
        monoSamples.withUnsafeBufferPointer { src in
            if let base = src.baseAddress {
                inputChannel.update(from: base, count: monoSamples.count)
            }
        }

        let ratio = SeshatConfig.sampleRate / inputSampleRate
        let outputCapacity = AVAudioFrameCount(Double(inputCapacity) * ratio + 1)
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: outputCapacity) else {
            logger.error("Failed to allocate output AVAudioPCMBuffer")
            throw SeshatError.resampleFailure
        }

        var error: NSError?
        var didFeed = false
        let status = converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if didFeed {
                outStatus.pointee = .endOfStream
                return nil
            }
            didFeed = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if let error {
            logger.error("AVAudioConverter.convert failed", error: error)
            throw SeshatError.resampleFailure
        }
        if status == .error {
            logger.error("AVAudioConverter.convert returned .error")
            throw SeshatError.resampleFailure
        }

        guard let outputChannel = outputBuffer.floatChannelData?[0] else {
            logger.error("Failed to access output channel data")
            throw SeshatError.resampleFailure
        }
        let outputCount = Int(outputBuffer.frameLength)
        let outputSamples = Array(UnsafeBufferPointer(start: outputChannel, count: outputCount))

        return try PCMBuffer(
            samples: outputSamples,
            sampleRate: SeshatConfig.sampleRate,
            channelCount: SeshatConfig.channelCount,
            timestamp: timestamp
        )
    }

    private let logger: SeshatLogger
    private let inputSampleRate: Double
    private let customResampleImpl: (@Sendable ([Float], ContinuousClock.Instant) throws -> PCMBuffer)?
}
