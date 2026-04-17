import AVFoundation
import Foundation
import SeshatCore

/// Production `AudioCapturing` conformer. Owns one AVAudioEngine at a time,
/// enforces single-active-capture, and yields 16 kHz mono Float32 `PCMBuffer`
/// values until `stop()` (or a runtime error) terminates the stream exactly once.
public actor AVAudioCaptureService: AudioCapturing {
    public init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio)
    ) {
        self.init(
            logger: logger,
            authorizationStatusProvider: {
                AVCaptureDevice.authorizationStatus(for: .audio)
            },
            engineDriver: .live(),
            resamplerFactory: { sampleRate, logger in
                try AudioResampler(
                    inputSampleRate: sampleRate,
                    logger: logger
                )
            }
        )
    }

    internal init(
        logger: SeshatLogger = SeshatLogger(category: SeshatLogCategory.audio),
        authorizationStatusProvider: @escaping @Sendable () -> AVAuthorizationStatus,
        engineDriver: AudioEngineDriver,
        resamplerFactory: @escaping @Sendable (Double, SeshatLogger) throws -> AudioResampler
    ) {
        self.logger = logger
        self.authorizationStatusProvider = authorizationStatusProvider
        self.engineDriver = engineDriver
        self.resamplerFactory = resamplerFactory
    }

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        // 1. Authorization check
        let status = authorizationStatusProvider()
        guard status == .authorized else {
            logger.info("Microphone authorization status \(status.rawValue); rejecting capture start")
            throw SeshatError.micPermissionDenied
        }

        // 2. Reject a second live stream
        guard !isCapturing || isTerminated else {
            logger.error("start() called while capture already live; rejecting second start")
            throw SeshatError.audioEngineFailure
        }

        // 3. Read input format and create resampler
        let inputFormat = engineDriver.inputFormat()
        let sampleRate = inputFormat.sampleRate
        let channelCount = Int(inputFormat.channelCount)

        let resampler: AudioResampler
        do {
            resampler = try resamplerFactory(sampleRate, logger)
        } catch {
            logger.error("Failed to create resampler", error: error)
            throw SeshatError.audioEngineFailure
        }

        // 4. Create stream
        let (stream, continuation) = AsyncThrowingStream<PCMBuffer, Error>.makeStream()

        // 5. Install tap, prepare, start engine
        do {
            try engineDriver.installTap { [weak self] buffer, _ in
                // Called on the engine's tap thread. Extract Sendable values only.
                let samples = Self.extractMonoSamples(from: buffer, channels: channelCount)
                let ts = ContinuousClock.now
                Task { [weak self] in
                    await self?.handleTapSamples(samples: samples, timestamp: ts)
                }
            }
            engineDriver.prepare()
            try engineDriver.start()
        } catch {
            logger.error("Engine startup failed", error: error)
            engineDriver.removeTap()
            engineDriver.stop()
            engineDriver.reset()
            continuation.finish()
            throw SeshatError.audioEngineFailure
        }

        // 6. Mark live and wire continuation
        self.continuation = continuation
        self.resampler = resampler
        self.isCapturing = true
        self.isTerminated = false

        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.handleContinuationTermination()
            }
        }

        return stream
    }

    public func stop() async {
        guard !isTerminated else {
            return  // idempotent
        }

        // First actor-visible terminal event wins: claim termination synchronously.
        isTerminated = true

        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()

        continuation?.finish()
        continuation = nil
        resampler = nil
        isCapturing = false
    }

    // MARK: - Actor-isolated tap handling

    private func handleTapSamples(samples: [Float], timestamp: ContinuousClock.Instant) async {
        guard !isTerminated, let resampler, let continuation else { return }

        do {
            let buffer = try await resampler.resample(
                monoSamples: samples,
                timestamp: timestamp
            )
            guard !isTerminated else { return }
            continuation.yield(buffer)
        } catch let seshatError as SeshatError {
            finishWithError(seshatError)
        } catch {
            logger.error("Upstream resample threw non-SeshatError; mapping to .resampleFailure", error: error)
            finishWithError(.resampleFailure)
        }
    }

    private func finishWithError(_ error: SeshatError) {
        guard !isTerminated else { return }
        isTerminated = true
        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()
        continuation?.finish(throwing: error)
        continuation = nil
        resampler = nil
        isCapturing = false
    }

    private func handleContinuationTermination() async {
        // Consumer cancelled / finished iterating. Treat as stop.
        guard !isTerminated else { return }
        isTerminated = true
        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()
        resampler = nil
        isCapturing = false
    }

    // MARK: - Sample extraction (nonisolated, called from tap thread)

    private static func extractMonoSamples(
        from buffer: AVAudioPCMBuffer,
        channels: Int
    ) -> [Float] {
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0, let channelData = buffer.floatChannelData else { return [] }

        if channels == 1 {
            let ptr = channelData[0]
            return Array(UnsafeBufferPointer(start: ptr, count: frameCount))
        }

        // Multi-channel: average all channels into mono.
        var result = [Float](repeating: 0, count: frameCount)
        let channelsCapped = min(channels, Int(buffer.format.channelCount))
        for c in 0..<channelsCapped {
            let ptr = channelData[c]
            for i in 0..<frameCount {
                result[i] += ptr[i]
            }
        }
        let divisor = Float(channelsCapped)
        for i in 0..<frameCount {
            result[i] /= divisor
        }
        return result
    }

    // MARK: - Stored state

    private let logger: SeshatLogger
    private let authorizationStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let engineDriver: AudioEngineDriver
    private let resamplerFactory: @Sendable (Double, SeshatLogger) throws -> AudioResampler
    private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var resampler: AudioResampler?
    private var isCapturing = false
    private var isTerminated = false
}
