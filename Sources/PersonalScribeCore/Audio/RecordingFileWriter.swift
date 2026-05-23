import AVFoundation
import Foundation

public protocol RecordingFileWriting: Sendable {
    func write(_ buffers: [PCMBuffer], to url: URL) throws
}

public struct RecordingFileWriter: RecordingFileWriting, Sendable {
    public init() {}

    public static func filename(
        for date: Date,
        calendar: Calendar = .current,
        fileManager: FileManager = .default,
        in directory: URL
    ) -> String {
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date
        )
        let stem = String(
            format: "%04d%02d%02d_%02d%02d%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0,
            components.hour ?? 0,
            components.minute ?? 0,
            components.second ?? 0
        )

        var suffix = 1
        while true {
            let candidate = suffix == 1 ? "\(stem).wav" : "\(stem)_\(suffix).wav"
            let candidateURL = directory.appendingPathComponent(candidate, isDirectory: false)
            guard !fileManager.fileExists(atPath: candidateURL.path) else {
                suffix += 1
                continue
            }
            return candidate
        }
    }

    public func write(_ buffers: [PCMBuffer], to url: URL) throws {
        let (samples, sampleRate, channelCount) = try coalesce(buffers)
        let sourceFormat = try makeSourceFormat(sampleRate: sampleRate, channelCount: channelCount)
        let fileSettings = makeFileSettings()
        let frameCount = AVAudioFrameCount(samples.count / channelCount)
        let fileManager = FileManager.default

        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let audioFile = try AVAudioFile(
            forWriting: url,
            settings: fileSettings,
            commonFormat: sourceFormat.commonFormat,
            interleaved: sourceFormat.isInterleaved
        )

        if frameCount > 0 {
            guard let buffer = AVAudioPCMBuffer(
                pcmFormat: sourceFormat,
                frameCapacity: frameCount
            ) else {
                throw PersonalScribeError.resampleFailure
            }
            buffer.frameLength = frameCount

            guard let channelData = buffer.floatChannelData else {
                throw PersonalScribeError.resampleFailure
            }

            samples.withUnsafeBufferPointer { source in
                guard let baseAddress = source.baseAddress else {
                    return
                }
                channelData[0].update(from: baseAddress, count: samples.count)
            }

            try audioFile.write(from: buffer)
        }

        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private func coalesce(
        _ buffers: [PCMBuffer]
    ) throws -> (samples: [Float], sampleRate: Double, channelCount: Int) {
        guard let first = buffers.first else {
            return ([], AppConfig.sampleRate, AppConfig.channelCount)
        }

        guard first.sampleRate == AppConfig.sampleRate,
              first.channelCount == AppConfig.channelCount
        else {
            throw PersonalScribeError.resampleFailure
        }

        var combinedSamples: [Float] = []
        combinedSamples.reserveCapacity(buffers.reduce(0) { $0 + $1.samples.count })
        for buffer in buffers {
            guard buffer.sampleRate == first.sampleRate,
                  buffer.channelCount == first.channelCount
            else {
                throw PersonalScribeError.resampleFailure
            }
            combinedSamples.append(contentsOf: buffer.samples)
        }

        return (combinedSamples, first.sampleRate, first.channelCount)
    }

    private func makeSourceFormat(sampleRate: Double, channelCount: Int) throws -> AVAudioFormat {
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount),
            interleaved: false
        ) else {
            throw PersonalScribeError.resampleFailure
        }
        return format
    }

    private func makeFileSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: AppConfig.sampleRate,
            AVNumberOfChannelsKey: AppConfig.channelCount,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
    }
}
