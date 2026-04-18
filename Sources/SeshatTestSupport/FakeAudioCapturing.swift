import Foundation
import SeshatCore

public actor FakeAudioCapturing: AudioCapturing {
    private let buffers: [PCMBuffer]
    private var programmedError: SeshatError?
    private let delayPerBuffer: Duration?
    private let levels: [Float]

    private var isCapturing = false
    private var didFinishStream = false
    private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var emissionTask: Task<Void, Never>?

    // Step 2.9 / 2.10: support an optional canned audio-level stream so
    // SessionCoordinator tests can observe level republishing without a
    // real engine.
    private var levelContinuation: AsyncStream<Float>.Continuation?
    private var pendingLevelStream: AsyncStream<Float>?
    private var levelEmissionTask: Task<Void, Never>?

    public init(
        buffers: [PCMBuffer] = [],
        error: SeshatError? = nil,
        delayPerBuffer: Duration? = nil,
        levels: [Float] = []
    ) {
        self.buffers = buffers
        self.programmedError = error
        self.delayPerBuffer = delayPerBuffer
        self.levels = levels
    }

    public func start() async throws -> AsyncThrowingStream<PCMBuffer, Error> {
        guard !isCapturing else {
            throw SeshatError.audioEngineFailure
        }

        isCapturing = true
        didFinishStream = false
        let errorToEmit = programmedError
        programmedError = nil

        var capturedContinuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
        let stream = AsyncThrowingStream<PCMBuffer, Error> { continuation in
            capturedContinuation = continuation
        }

        continuation = capturedContinuation
        emissionTask = Task {
            for buffer in self.buffers {
                if let delayPerBuffer = self.delayPerBuffer {
                    try? await Task.sleep(for: delayPerBuffer)
                }

                if Task.isCancelled {
                    return
                }

                self.yield(buffer)
            }

            if let programmedError = errorToEmit {
                self.finishStream(throwing: programmedError)
            }
        }

        // Prepare a level stream; emission is driven lazily when
        // `audioLevelStream()` is called so the PCM path stays unchanged.
        let (levelStream, levelContinuation) = AsyncStream<Float>.makeStream()
        self.levelContinuation = levelContinuation
        self.pendingLevelStream = levelStream

        return stream
    }

    public func stop() async {
        emissionTask?.cancel()
        emissionTask = nil
        levelEmissionTask?.cancel()
        levelEmissionTask = nil
        finishStream()
        levelContinuation?.finish()
        levelContinuation = nil
        pendingLevelStream = nil
    }

    public func audioLevelStream() async -> AsyncStream<Float> {
        if let stream = pendingLevelStream {
            pendingLevelStream = nil

            // If canned levels were provided, schedule them for emission on
            // first subscription. They emit as fast as the consumer can
            // receive.
            if !levels.isEmpty {
                let captured = levels
                levelEmissionTask = Task { [weak self] in
                    for level in captured {
                        if Task.isCancelled { return }
                        await self?.yieldLevel(level)
                    }
                }
            }

            return stream
        }
        return AsyncStream { continuation in
            continuation.finish()
        }
    }

    private func yieldLevel(_ level: Float) {
        levelContinuation?.yield(level)
    }

    private func yield(_ buffer: PCMBuffer) {
        guard !didFinishStream else { return }
        continuation?.yield(buffer)
    }

    private func finishStream(throwing error: SeshatError? = nil) {
        guard !didFinishStream else { return }
        didFinishStream = true
        isCapturing = false
        levelEmissionTask?.cancel()
        levelEmissionTask = nil
        levelContinuation?.finish()
        levelContinuation = nil
        pendingLevelStream = nil

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }

        continuation = nil
        emissionTask = nil
    }
}
