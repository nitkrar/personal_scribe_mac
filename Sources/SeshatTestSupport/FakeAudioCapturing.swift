import Foundation
import SeshatCore

public actor FakeAudioCapturing: AudioCapturing {
    private let buffers: [PCMBuffer]
    private var programmedError: SeshatError?
    private let delayPerBuffer: Duration?

    private var isCapturing = false
    private var didFinishStream = false
    private var continuation: AsyncThrowingStream<PCMBuffer, Error>.Continuation?
    private var emissionTask: Task<Void, Never>?

    public init(
        buffers: [PCMBuffer] = [],
        error: SeshatError? = nil,
        delayPerBuffer: Duration? = nil
    ) {
        self.buffers = buffers
        self.programmedError = error
        self.delayPerBuffer = delayPerBuffer
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

        return stream
    }

    public func stop() async {
        emissionTask?.cancel()
        emissionTask = nil
        finishStream()
    }

    private func yield(_ buffer: PCMBuffer) {
        guard !didFinishStream else { return }
        continuation?.yield(buffer)
    }

    private func finishStream(throwing error: SeshatError? = nil) {
        guard !didFinishStream else { return }
        didFinishStream = true
        isCapturing = false

        if let error {
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }

        continuation = nil
        emissionTask = nil
    }
}
