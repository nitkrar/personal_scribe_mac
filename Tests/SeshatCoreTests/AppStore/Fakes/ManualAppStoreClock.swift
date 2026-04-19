import Foundation
import SeshatCore

final class ManualAppStoreClock: @unchecked Sendable, AppStoreClock {
    private struct SleepRequest {
        let deadline: Duration
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentTime: Duration
    private var sleepers: [UUID: SleepRequest] = [:]

    init(now: Duration = .zero) {
        currentTime = now
    }

    func now() -> Duration {
        withLock {
            currentTime
        }
    }

    func sleep(for duration: Duration) async throws {
        let id = UUID()
        let deadline = withLock {
            currentTime + duration
        }

        if deadline <= now() {
            return
        }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let shouldResumeImmediately = withLock { () -> Bool in
                    if currentTime >= deadline {
                        return true
                    }

                    sleepers[id] = SleepRequest(
                        deadline: deadline,
                        continuation: continuation
                    )
                    return false
                }

                if shouldResumeImmediately {
                    continuation.resume()
                }
            }
        } onCancel: {
            let request = self.withLock {
                self.sleepers.removeValue(forKey: id)
            }
            request?.continuation.resume(throwing: CancellationError())
        }
    }

    func advance(by duration: Duration) async {
        let yieldIterations = 10

        await yieldUntilSleepersStabilize(maxIterations: yieldIterations)

        let readyContinuations = withLock { () -> [CheckedContinuation<Void, Error>] in
            currentTime = currentTime + duration

            let readyIDs = sleepers.compactMap { id, request in
                request.deadline <= currentTime ? id : nil
            }

            return readyIDs.compactMap { id in
                sleepers.removeValue(forKey: id)?.continuation
            }
        }

        for continuation in readyContinuations {
            continuation.resume()
        }

        if readyContinuations.isEmpty == false {
            await yieldUntilSleepersStabilize(maxIterations: yieldIterations)
        }
    }

    private func yieldUntilSleepersStabilize(maxIterations: Int) async {
        var observedChange = false
        var previousSleeperCount = withLock { sleepers.count }

        for _ in 0..<maxIterations {
            await Task.yield()

            let currentSleeperCount = withLock { sleepers.count }
            if currentSleeperCount != previousSleeperCount {
                observedChange = true
            } else if observedChange {
                return
            }

            previousSleeperCount = currentSleeperCount
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}
