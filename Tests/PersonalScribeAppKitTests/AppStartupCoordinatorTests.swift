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

    private func waitUntil(
        maxIterations: Int = 500,
        condition: @escaping @Sendable () -> Bool
    ) async {
        for _ in 0..<maxIterations {
            if condition() {
                return
            }

            await Task.yield()
        }

        XCTFail("Timed out waiting for condition")
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
