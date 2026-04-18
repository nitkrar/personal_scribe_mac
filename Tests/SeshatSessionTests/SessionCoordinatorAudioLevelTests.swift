import XCTest
import SeshatCore
import SeshatTestSupport
@testable import SeshatSession

/// Tests for the phase-2 step 2.10 additive audio-level republishing.
/// `SessionCoordinator` subscribes to the capture service's level stream and
/// multiplexes values out via its own `audioLevelStream()` so SwiftUI
/// surfaces (Sprint 2 pill, Phase 3 onboarding) can bind directly without
/// holding a reference to the underlying capture actor.
final class SessionCoordinatorAudioLevelTests: XCTestCase {
    func testAudioLevelStreamRepublishesLevelsDuringRecording() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 1_600),
            timestamp: ContinuousClock().now
        )
        // Avoid 0.0 at the head of the canned list — the stream yields the
        // cached initial level (0.0) on subscription, which we discard
        // below. Using distinct non-zero values keeps the assertion crisp.
        let canned: [Float] = [0.15, 0.25, 0.5, 0.75, 0.95]
        let capture = FakeAudioCapturing(
            buffers: [buffer],
            levels: canned
        )
        let transcriber = FakeTranscriber(
            result: .init(text: "", audioDuration: .zero, processingDuration: .zero)
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let levelStream = await coordinator.audioLevelStream()
        var iterator = levelStream.makeAsyncIterator()

        // Consume and assert the initial cached 0.0 the stream yields on
        // subscription (matching the `stateStream()` pattern).
        let initial = await iterator.next()
        XCTAssertEqual(initial, 0.0)

        await coordinator.toggle() // idle -> recording -> (finishes buffers)

        // Collect canned.count levels with a small deadline.
        var observed: [Float] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))
        while observed.count < canned.count, ContinuousClock.now < deadline {
            guard let level = await iterator.next() else { break }
            observed.append(level)
        }

        // Drive coordinator back to idle to let the test finish cleanly.
        await coordinator.toggle()

        XCTAssertEqual(observed, canned)
    }

    func testAudioLevelStreamDeliversInitialSubscriptionBeforeRecording() async {
        let capture = FakeAudioCapturing()
        let transcriber = FakeTranscriber(
            result: .init(text: "", audioDuration: .zero, processingDuration: .zero)
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        // Subscribing before any recording starts must not block; the stream
        // simply has no values yet. We don't iterate — just prove we can get
        // a stream back synchronously (modulo actor hop).
        let levelStream = await coordinator.audioLevelStream()
        _ = levelStream.makeAsyncIterator()
        // If this line is reached the test has its guarantee.
    }

    func testMultipleSubscribersEachReceiveEveryLevel() async throws {
        let buffer = try PCMBuffer(
            samples: Array(repeating: 0, count: 1_600),
            timestamp: ContinuousClock().now
        )
        let canned: [Float] = [0.1, 0.2, 0.3]
        let capture = FakeAudioCapturing(
            buffers: [buffer],
            levels: canned
        )
        let transcriber = FakeTranscriber(
            result: .init(text: "", audioDuration: .zero, processingDuration: .zero)
        )
        let coordinator = SessionCoordinator(
            capture: capture,
            transcriber: transcriber,
            logger: SeshatLogger(category: SeshatLogCategory.session)
        )

        let streamA = await coordinator.audioLevelStream()
        let streamB = await coordinator.audioLevelStream()

        var iterA = streamA.makeAsyncIterator()
        var iterB = streamB.makeAsyncIterator()

        // Discard the initial cached 0.0 value on each subscription.
        _ = await iterA.next()
        _ = await iterB.next()

        await coordinator.toggle()

        var observedA: [Float] = []
        var observedB: [Float] = []
        let deadline = ContinuousClock.now.advanced(by: .seconds(3))

        while (observedA.count < canned.count || observedB.count < canned.count),
              ContinuousClock.now < deadline {
            if observedA.count < canned.count, let value = await iterA.next() {
                observedA.append(value)
            }
            if observedB.count < canned.count, let value = await iterB.next() {
                observedB.append(value)
            }
        }

        await coordinator.toggle()

        XCTAssertEqual(observedA, canned)
        XCTAssertEqual(observedB, canned)
    }
}
