import AVFoundation
import Foundation
import PersonalScribeCore

public protocol AudioLevelMonitoring: Sendable {
    func start() async throws -> AsyncStream<Float>
    func stop() async
}

/// Short-lived microphone meter for setup. It owns no recording stream and
/// must be stopped before the normal capture pipeline starts.
public actor StandaloneAudioLevelMonitor: AudioLevelMonitoring {
    private let authorizationStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let engineDriver: AudioEngineDriver
    private let inputDeviceProvider: any AudioInputDeviceProviding
    private var continuation: AsyncStream<Float>.Continuation?
    private var isRunning = false

    public init(
        inputDeviceProvider: any AudioInputDeviceProviding = NoOpAudioInputDeviceProvider()
    ) {
        self.init(
            authorizationStatusProvider: {
                AVCaptureDevice.authorizationStatus(for: .audio)
            },
            engineDriver: .live(),
            inputDeviceProvider: inputDeviceProvider
        )
    }

    internal init(
        authorizationStatusProvider: @escaping @Sendable () -> AVAuthorizationStatus,
        engineDriver: AudioEngineDriver,
        inputDeviceProvider: any AudioInputDeviceProviding
    ) {
        self.authorizationStatusProvider = authorizationStatusProvider
        self.engineDriver = engineDriver
        self.inputDeviceProvider = inputDeviceProvider
    }

    public func start() async throws -> AsyncStream<Float> {
        stopInternal()
        guard authorizationStatusProvider() == .authorized else {
            throw PersonalScribeError.micPermissionDenied
        }

        do {
            try engineDriver.applyInputDevice(uid: inputDeviceProvider.selectedDeviceID)
            let format = engineDriver.inputFormat()
            let channelCount = Int(format.channelCount)
            guard format.sampleRate > 0, channelCount > 0 else {
                throw PersonalScribeError.audioEngineFailure
            }
            let (stream, continuation) = AsyncStream<Float>.makeStream()
            self.continuation = continuation
            try engineDriver.installTap { buffer, _ in
                let samples = Self.extractMonoSamples(from: buffer, channels: channelCount)
                continuation.yield(AudioLevelCalculator.normalizedLevel(samples: samples))
            }
            engineDriver.prepare()
            try engineDriver.start()
            isRunning = true
            continuation.onTermination = { [weak self] _ in
                Task { await self?.stop() }
            }
            return stream
        } catch {
            stopInternal()
            throw PersonalScribeError.audioEngineFailure
        }
    }

    public func stop() async {
        stopInternal()
    }

    private func stopInternal() {
        guard isRunning || continuation != nil else { return }
        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()
        continuation?.finish()
        continuation = nil
        isRunning = false
    }

    private nonisolated static func extractMonoSamples(
        from buffer: AVAudioPCMBuffer,
        channels: Int
    ) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return [] }
        if channels == 1 {
            return Array(UnsafeBufferPointer(start: channelData[0], count: frameCount))
        }
        let channelCount = min(channels, Int(buffer.format.channelCount))
        var samples = [Float](repeating: 0, count: frameCount)
        for channel in 0..<channelCount {
            for frame in 0..<frameCount {
                samples[frame] += channelData[channel][frame]
            }
        }
        let divisor = Float(channelCount)
        return samples.map { $0 / divisor }
    }
}
