import AVFoundation
import Foundation
import PersonalScribeCore

/// Production `AudioCapturer` conformer. Owns one AVAudioEngine at a time,
/// enforces single-active-capture, and yields 16 kHz mono Float32 `PCMBuffer`
/// values until `stop()` (or a runtime error) terminates the stream exactly once.
public actor AVAudioCaptureService: AudioCapturer {
    public init(
        logger: PersonalScribeLogger,
        inputDeviceProvider: any AudioInputDeviceProviding = NoOpAudioInputDeviceProvider(),
        shouldMuteOutput: @escaping @Sendable () -> Bool = { false }
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
            },
            inputDeviceProvider: inputDeviceProvider,
            shouldMuteOutput: shouldMuteOutput,
            systemAudioMuter: SystemAudioMuter()
        )
    }

    internal init(
        logger: PersonalScribeLogger,
        authorizationStatusProvider: @escaping @Sendable () -> AVAuthorizationStatus,
        engineDriver: AudioEngineDriver,
        resamplerFactory: @escaping @Sendable (Double, PersonalScribeLogger) throws -> AudioResampler,
        inputDeviceProvider: any AudioInputDeviceProviding = NoOpAudioInputDeviceProvider(),
        shouldMuteOutput: @escaping @Sendable () -> Bool = { false },
        systemAudioMuter: SystemAudioMuter = SystemAudioMuter()
    ) {
        self.logger = logger
        self.authorizationStatusProvider = authorizationStatusProvider
        self.engineDriver = engineDriver
        self.resamplerFactory = resamplerFactory
        self.inputDeviceProvider = inputDeviceProvider
        self.shouldMuteOutput = shouldMuteOutput
        self.systemAudioMuter = systemAudioMuter
    }

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        // 1. Authorization check
        let status = authorizationStatusProvider()
        guard status == .authorized else {
            logger.info("Microphone authorization status \(status.rawValue); rejecting capture start")
            throw PersonalScribeError.micPermissionDenied
        }

        // 2. Reject a second live stream
        guard !isCapturing || isTerminated else {
            logger.error("start() called while capture already live; rejecting second start")
            throw PersonalScribeError.audioEngineFailure
        }

        // 3. Create streams
        let (stream, continuation) = AsyncThrowingStream<PCMBuffer, Error>.makeStream()
        let (levelStream, levelContinuation) = AsyncStream<Float>.makeStream()

        // 4. Mute system audio output if the user opted in. Placed after
        // the auth / double-start checks so those never leave the machine
        // muted. Any failure after this point MUST call
        // `systemAudioMuter.restoreIfNeeded()`.
        if shouldMuteOutput() {
            systemAudioMuter.muteIfNeeded()
        }

        if !isObservingConfigurationChanges {
            isObservingConfigurationChanges = true
            engineDriver.observeConfigurationChanges { [weak self] in
                Task { [weak self] in await self?.handleConfigurationChange() }
            }
        }

        // 5. Read the hardware format, then install the tap and start.
        let startedAt = ContinuousClock.now
        let sampleRate: Double
        let resampler: AudioResampler
        do {
            applySelectedInputDevice()
            let inputFormat = engineDriver.inputFormat()
            sampleRate = inputFormat.sampleRate
            let channelCount = Int(inputFormat.channelCount)
            // A device mid-switch can report no format; installing a tap
            // then raises an uncatchable ObjC exception.
            guard sampleRate > 0, channelCount > 0 else {
                throw CaptureStartError.noUsableFormat(sampleRate: sampleRate, channels: channelCount)
            }
            let deviceID = inputDeviceProvider.effectiveDeviceID
            let deviceName = inputDeviceProvider.availableDevices().first { $0.id == deviceID }?.name ?? "system default"
            logger.info("capture_starting — device=\(deviceName) sampleRate=\(Int(sampleRate)) channels=\(channelCount)")
            resampler = try resamplerFactory(sampleRate, logger)
            try installForwardingTap(channelCount: channelCount)
            engineDriver.prepare()
            try engineDriver.start()
            runningSampleRate = sampleRate
            runningChannelCount = channelCount
        } catch {
            let nsError = error as NSError
            logger.error("Engine startup failed (\(nsError.domain) \(nsError.code))", error: error)
            systemAudioMuter.restoreIfNeeded()
            engineDriver.removeTap()
            engineDriver.stop()
            engineDriver.reset()
            continuation.finish()
            levelContinuation.finish()
            throw PersonalScribeError.audioEngineFailure
        }
        captureStartedAt = ContinuousClock.now
        receivedFrames = 0
        receivedSeconds = 0
        peakSample = 0
        logger.info("capture_engine_started — afterMs=\(Self.milliseconds(captureStartedAt! - startedAt))")

        // 6. Mark live and wire continuations
        self.continuation = continuation
        self.levelContinuation = levelContinuation
        self.levelSampleRate = sampleRate
        self.levelAccumulator.removeAll(keepingCapacity: true)
        self.levelAccumulatedFrames = 0
        self.resampler = resampler
        self.isCapturing = true
        self.isTerminated = false

        continuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.handleContinuationTermination()
            }
        }

        // A pending level-stream consumer that cancels while capture is still
        // live should not tear down the PCM stream — just drop the level
        // continuation so future emits no-op.
        levelContinuation.onTermination = { [weak self] _ in
            Task { [weak self] in
                await self?.dropLevelContinuation()
            }
        }

        self.pendingLevelStream = levelStream

        return stream
    }

    /// Returns an `AsyncStream<Float>` of normalized audio-level samples
    /// published at roughly 10 Hz. Must be called after a successful
    /// `start()` — before then (or after `stop()`), it returns an
    /// immediately-finished stream. The stream terminates when `stop()` is
    /// called or capture fails.
    ///
    /// Cadence comes from buffer size / sample rate: the service accumulates
    /// ≥ 100 ms of input-rate audio, computes RMS across the accumulator,
    /// emits a normalized `[0, 1]` level, and resets. No wall-clock timer.
    public func audioLevelStream() async -> AsyncStream<Float> {
        if let stream = pendingLevelStream {
            pendingLevelStream = nil
            return stream
        }
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    public func stop() async {
        guard !isTerminated else {
            return  // idempotent
        }

        // First actor-visible terminal event wins: claim termination synchronously.
        isTerminated = true
        if captureStartedAt != nil {
            logger.info("capture_stopped — receivedSeconds=\(String(format: "%.1f", receivedSeconds)) peak=\(String(format: "%.3f", peakSample))")
            captureStartedAt = nil
        }

        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()
        systemAudioMuter.restoreIfNeeded()

        continuation?.finish()
        continuation = nil
        levelContinuation?.finish()
        levelContinuation = nil
        pendingLevelStream = nil
        levelAccumulator.removeAll(keepingCapacity: false)
        levelAccumulatedFrames = 0
        resampler = nil
        isCapturing = false
    }

    // MARK: - Actor-isolated tap handling

    /// A missing selected device falls back to the system default; a
    /// failure here must never block recording.
    private func applySelectedInputDevice() {
        do {
            try engineDriver.applyInputDevice(uid: inputDeviceProvider.selectedDeviceID)
        } catch {
            logger.error("Failed to apply selected audio input device; proceeding with system default", error: error)
        }
    }

    private func installForwardingTap(channelCount: Int) throws {
        try engineDriver.installTap { [weak self] buffer, _ in
            // Called on the engine's tap thread. Extract Sendable values only.
            let samples = Self.extractMonoSamples(from: buffer, channels: channelCount)
            let ts = ContinuousClock.now
            Task { [weak self] in
                await self?.handleTapSamples(samples: samples, timestamp: ts)
            }
        }
    }

    /// The input device went away or changed mid-recording (e.g. AirPods put
    /// back in their case). Restart on the current input and keep feeding the
    /// same stream; end the recording with an error if that isn't possible.
    private func handleConfigurationChange() async {
        // macOS also posts this when nothing changed (e.g. right after
        // start). Restart when the device went away (engine stopped) or the
        // hardware format no longer matches what capture is running at.
        guard isCapturing, !isTerminated else { return }
        let hardware = engineDriver.inputFormat()
        let formatChanged = hardware.sampleRate != runningSampleRate || Int(hardware.channelCount) != runningChannelCount
        guard formatChanged || !engineDriver.isRunning else { return }
        engineDriver.removeTap()
        engineDriver.stop()
        do {
            applySelectedInputDevice()
            let format = engineDriver.inputFormat()
            let channelCount = Int(format.channelCount)
            guard format.sampleRate > 0, channelCount > 0 else {
                throw PersonalScribeError.audioEngineFailure
            }
            resampler = try resamplerFactory(format.sampleRate, logger)
            runningSampleRate = format.sampleRate
            runningChannelCount = channelCount
            levelSampleRate = format.sampleRate
            levelAccumulator.removeAll(keepingCapacity: true)
            levelAccumulatedFrames = 0
            try installForwardingTap(channelCount: channelCount)
            engineDriver.prepare()
            try engineDriver.start()
            let deviceID = inputDeviceProvider.effectiveDeviceID
            let deviceName = inputDeviceProvider.availableDevices().first { $0.id == deviceID }?.name ?? "system default"
            logger.info("capture_device_changed — restarted on device=\(deviceName) sampleRate=\(Int(format.sampleRate))")
        } catch {
            logger.error("Capture could not restart after the input device changed", error: error)
            finishWithError(.audioEngineFailure)
        }
    }

    private func handleTapSamples(samples: [Float], timestamp: ContinuousClock.Instant) async {
        guard !isTerminated, let resampler, let continuation else { return }
        if receivedFrames == 0, let captureStartedAt {
            logger.info("capture_first_audio — afterMs=\(Self.milliseconds(timestamp - captureStartedAt))")
        }
        receivedFrames += samples.count
        if levelSampleRate > 0 { receivedSeconds += Double(samples.count) / levelSampleRate }
        peakSample = max(peakSample, samples.lazy.map(abs).max() ?? 0)

        // Step 2.9: additive audio-level emission. Runs on the actor so it's
        // serialized against stop()/finishWithError() — no level yields
        // happen after termination.
        emitLevelIfWindowComplete(tapSamples: samples)

        do {
            let buffer = try await resampler.resample(
                monoSamples: samples,
                timestamp: timestamp
            )
            guard !isTerminated else { return }
            continuation.yield(buffer)
        } catch let seshatError as PersonalScribeError {
            finishWithError(seshatError)
        } catch {
            logger.error("Upstream resample threw non-PersonalScribeError; mapping to .resampleFailure", error: error)
            finishWithError(.resampleFailure)
        }
    }

    /// Accumulate `tapSamples` into the 100 ms window. When the window fills,
    /// compute `normalizedLevel` over the entire window, yield it on the
    /// level continuation, and reset the accumulator. Buffers that arrive
    /// larger than the window still yield one sample and keep the remainder
    /// for the next window (so cadence stays ~10 Hz regardless of input
    /// buffer size).
    private func emitLevelIfWindowComplete(tapSamples: [Float]) {
        guard let levelContinuation, levelSampleRate > 0 else { return }
        let framesPerWindow = Int((levelSampleRate * levelWindowSeconds).rounded())
        guard framesPerWindow > 0 else { return }

        levelAccumulator.append(contentsOf: tapSamples)
        levelAccumulatedFrames += tapSamples.count

        // Drain as many full windows as have accumulated. This protects the
        // cadence contract when a very large buffer arrives at once.
        while levelAccumulatedFrames >= framesPerWindow {
            let window = Array(levelAccumulator.prefix(framesPerWindow))
            let level = AudioLevelCalculator.normalizedLevel(samples: window)
            levelContinuation.yield(level)

            levelAccumulator.removeFirst(framesPerWindow)
            levelAccumulatedFrames -= framesPerWindow
        }
    }

    private func dropLevelContinuation() {
        levelContinuation = nil
        pendingLevelStream = nil
    }

    private func finishWithError(_ error: PersonalScribeError) {
        guard !isTerminated else { return }
        isTerminated = true
        engineDriver.removeTap()
        engineDriver.stop()
        engineDriver.reset()
        systemAudioMuter.restoreIfNeeded()
        continuation?.finish(throwing: error)
        continuation = nil
        levelContinuation?.finish()
        levelContinuation = nil
        pendingLevelStream = nil
        levelAccumulator.removeAll(keepingCapacity: false)
        levelAccumulatedFrames = 0
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
        systemAudioMuter.restoreIfNeeded()
        levelContinuation?.finish()
        levelContinuation = nil
        pendingLevelStream = nil
        levelAccumulator.removeAll(keepingCapacity: false)
        levelAccumulatedFrames = 0
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

    private let logger: PersonalScribeLogger
    private let authorizationStatusProvider: @Sendable () -> AVAuthorizationStatus
    private let engineDriver: AudioEngineDriver
    private let resamplerFactory: @Sendable (Double, PersonalScribeLogger) throws -> AudioResampler
    private let inputDeviceProvider: any AudioInputDeviceProviding
    private let shouldMuteOutput: @Sendable () -> Bool
    private var systemAudioMuter: SystemAudioMuter
    private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var resampler: AudioResampler?
    private var isCapturing = false
    private var isTerminated = false
    /// Once-per-recording diagnostics: when audio started, how much arrived, how loud.
    private var captureStartedAt: ContinuousClock.Instant?
    private var receivedFrames = 0
    private var receivedSeconds: Double = 0
    private var isObservingConfigurationChanges = false
    /// Hardware format capture is running at; a configuration change only
    /// needs a restart when this no longer matches.
    private var runningSampleRate: Double = 0
    private var runningChannelCount = 0
    private var peakSample: Float = 0

    // Step 2.9: audio-level stream state.
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var pendingLevelStream: AsyncStream<Float>?
    private var levelSampleRate: Double = 0
    private var levelAccumulator: [Float] = []
    private var levelAccumulatedFrames: Int = 0
    /// 100 ms window → ~10 Hz emission cadence.
    private let levelWindowSeconds: Double = 0.1

    private enum CaptureStartError: Error {
        case noUsableFormat(sampleRate: Double, channels: Int)
    }

    private static func milliseconds(_ duration: Duration) -> Int {
        Int(duration.components.seconds * 1_000 + duration.components.attoseconds / 1_000_000_000_000_000)
    }

}
