@preconcurrency import AVFoundation
import CoreML
import Foundation
@preconcurrency import WhisperKit

final class BufferFedWhisperKitAudioProcessor: AudioProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private let audioProcessor = AudioProcessor()
    private var streamingContinuation: AsyncThrowingStream<[Float], Error>.Continuation?

    static func loadAudio(
        fromPath audioFilePath: String,
        channelMode: ChannelMode,
        startTime: Double?,
        endTime: Double?,
        maxReadFrameSize: AVAudioFrameCount?
    ) throws -> AVAudioPCMBuffer {
        try AudioProcessor.loadAudio(
            fromPath: audioFilePath,
            channelMode: channelMode,
            startTime: startTime,
            endTime: endTime,
            maxReadFrameSize: maxReadFrameSize
        )
    }

    static func loadAudio(
        at audioPaths: [String],
        channelMode: ChannelMode
    ) async -> [Result<[Float], Error>] {
        await AudioProcessor.loadAudio(at: audioPaths, channelMode: channelMode)
    }

    static func padOrTrimAudio(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int,
        saveSegment: Bool
    ) -> MLMultiArray? {
        AudioProcessor.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: saveSegment
        )
    }

    var audioSamples: ContiguousArray<Float> {
        lock.withLock { audioProcessor.audioSamples }
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.withLock {
            audioProcessor.purgeAudioSamples(keepingLast: keep)
        }
    }

    var relativeEnergy: [Float] {
        lock.withLock { audioProcessor.relativeEnergy }
    }

    var relativeEnergyWindow: Int {
        get { lock.withLock { audioProcessor.relativeEnergyWindow } }
        set {
            lock.withLock {
                audioProcessor.relativeEnergyWindow = newValue
            }
        }
    }

    func startRecordingLive(
        inputDeviceID: DeviceID?,
        callback: (([Float]) -> Void)?
    ) throws {
        _ = inputDeviceID
        lock.withLock {
            audioProcessor.audioSamples = []
            audioProcessor.audioEnergy = []
            audioProcessor.audioBufferCallback = callback
        }
    }

    func startStreamingRecordingLive(
        inputDeviceID: DeviceID?
    ) -> (AsyncThrowingStream<[Float], Error>, AsyncThrowingStream<[Float], Error>.Continuation) {
        _ = inputDeviceID
        let (stream, continuation) = AsyncThrowingStream<[Float], Error>.makeStream(
            bufferingPolicy: .unbounded
        )
        lock.withLock {
            audioProcessor.audioSamples = []
            audioProcessor.audioEnergy = []
            audioProcessor.audioBufferCallback = { samples in
                continuation.yield(samples)
            }
            streamingContinuation = continuation
        }
        return (stream, continuation)
    }

    func pauseRecording() {}

    func stopRecording() {
        let continuation = lock.withLock { () -> AsyncThrowingStream<[Float], Error>.Continuation? in
            let continuation = streamingContinuation
            streamingContinuation = nil
            audioProcessor.audioBufferCallback = nil
            return continuation
        }
        continuation?.finish()
    }

    func resumeRecordingLive(
        inputDeviceID: DeviceID?,
        callback: (([Float]) -> Void)?
    ) throws {
        _ = inputDeviceID
        lock.withLock {
            if let callback {
                audioProcessor.audioBufferCallback = callback
            }
        }
    }

    func padOrTrim(
        fromArray audioArray: [Float],
        startAt startIndex: Int,
        toLength frameLength: Int
    ) -> (any AudioProcessorOutputType)? {
        AudioProcessor.padOrTrimAudio(
            fromArray: audioArray,
            startAt: startIndex,
            toLength: frameLength,
            saveSegment: false
        )
    }

    func append(samples: [Float]) {
        guard !samples.isEmpty else {
            return
        }

        lock.withLock {
            audioProcessor.processBuffer(samples)
        }
    }
}
