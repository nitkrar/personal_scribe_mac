import Foundation
import XCTest
@testable import PersonalScribeAppKit

@MainActor
final class AppStartupCoordinatorTests: XCTestCase {
    func testStartTriggersHotkeyBeforePreparation() async {
        let recorder = StartupEventRecorder()

        let coordinator = AppStartupCoordinator(
            hotkeyDelay: .zero,
            prepareDelay: .zero,
            startHotkeyMonitor: {
                recorder.record("hotkey")
            },
            prepareTranscriber: {
                recorder.record("prepare")
            },
            sleep: { _ in }
        )

        coordinator.start()

        await waitUntil { recorder.snapshot() == ["hotkey", "prepare"] }
        XCTAssertEqual(recorder.snapshot(), ["hotkey", "prepare"])
    }

    func testStartIsIdempotent() async {
        let counter = StartupCounter()

        let coordinator = AppStartupCoordinator(
            hotkeyDelay: .zero,
            prepareDelay: .zero,
            startHotkeyMonitor: {
                counter.incrementHotkey()
            },
            prepareTranscriber: {
                counter.incrementPrepare()
            },
            sleep: { _ in }
        )

        coordinator.start()
        coordinator.start()

        await waitUntil {
            let counts = counter.snapshot()
            return counts.hotkeyCount == 1 && counts.prepareCount == 1
        }
        let counts = counter.snapshot()
        XCTAssertEqual(counts.hotkeyCount, 1)
        XCTAssertEqual(counts.prepareCount, 1)
    }

    /// Wall-clock polling loop (project memory: `condition-based-waiting`).
    /// Replaces the previous `Task.yield()`-only loop which flaked because
    /// `coordinator.start()` schedules a detached Task whose forward progress
    /// isn't guaranteed by cooperative yielding alone. Real-time deadline
    /// keeps the test fast in the common case but robust under CI load.
    private func waitUntil(
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(5),
        condition: @escaping @Sendable () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if condition() {
                return
            }
            try? await Task.sleep(for: pollInterval, tolerance: pollInterval)
        }
        XCTFail("Timed out waiting for condition after \(timeout)")
    }
}

private final class StartupEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [String] = []

    func record(_ event: String) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func snapshot() -> [String] {
        lock.lock()
        let snapshot = events
        lock.unlock()
        return snapshot
    }
}

private final class StartupCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var hotkeyCount = 0
    private var prepareCount = 0

    func incrementHotkey() {
        lock.lock()
        hotkeyCount += 1
        lock.unlock()
    }

    func incrementPrepare() {
        lock.lock()
        prepareCount += 1
        lock.unlock()
    }

    func snapshot() -> (hotkeyCount: Int, prepareCount: Int) {
        lock.lock()
        let snapshot = (hotkeyCount, prepareCount)
        lock.unlock()
        return snapshot
    }
}
