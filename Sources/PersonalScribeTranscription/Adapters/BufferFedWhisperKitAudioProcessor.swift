@preconcurrency import AVFoundation
import CoreML
import Foundation
@preconcurrency import WhisperKit

final class BufferFedWhisperKitAudioProcessor: AudioProcessing, @unchecked Sendable {
    private let lock = NSLock()
    private var audioSamplesStorage: ContiguousArray<Float> = []
    private var audioEnergyStorage: [(rel: Float, avg: Float, max: Float, min: Float)] = []
    private var relativeEnergyWindowStorage = 20
    private var callback: (([Float]) -> Void)?
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
        lock.withLock { audioSamplesStorage }
    }

    func purgeAudioSamples(keepingLast keep: Int) {
        lock.withLock {
            if audioSamplesStorage.count > keep {
                audioSamplesStorage.removeFirst(audioSamplesStorage.count - keep)
            }
        }
    }

    var relativeEnergy: [Float] {
        lock.withLock { audioEnergyStorage.map { $0.rel } }
    }

    var relativeEnergyWindow: Int {
        get { lock.withLock { relativeEnergyWindowStorage } }
        set { lock.withLock { relativeEnergyWindowStorage = newValue } }
    }

    func startRecordingLive(
        inputDeviceID: DeviceID?,
        callback: (([Float]) -> Void)?
    ) throws {
        _ = inputDeviceID
        lock.withLock {
            audioSamplesStorage = []
            audioEnergyStorage = []
            self.callback = callback
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
            audioSamplesStorage = []
            audioEnergyStorage = []
            callback = { samples in
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
            callback = nil
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
                self.callback = callback
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

        let callback = lock.withLock { () -> (([Float]) -> Void)? in
            audioSamplesStorage.append(contentsOf: samples)

            let referenceEnergy = audioEnergyStorage
                .suffix(relativeEnergyWindowStorage)
                .map { $0.avg }
                .min()
            let relativeEnergy = AudioProcessor.calculateRelativeEnergy(
                of: samples,
                relativeTo: referenceEnergy
            )
            let signalEnergy = AudioProcessor.calculateEnergy(of: samples)
            audioEnergyStorage.append((
                rel: relativeEnergy,
                avg: signalEnergy.avg,
                max: signalEnergy.max,
                min: signalEnergy.min
            ))

            return self.callback
        }

        callback?(samples)
    }
}
