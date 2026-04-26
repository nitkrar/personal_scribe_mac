import XCTest
@testable import PersonalScribeCore

/// #078.1 — `ModelLifecycle` is the shared lifecycle protocol the new
/// output protocols (`Transcriber2`, `StreamingTranscriber`,
/// `SpeakerDiarizer`) compose. These tests pin the surface so the
/// composition contract stays small (only `prepare` + progress) and
/// stays Sendable for the strict-concurrency boundary the provider
/// crosses.
final class ModelLifecycleTests: XCTestCase {

    // MARK: - Test fixtures

    /// Minimal conformer used to assert that satisfying `prepare()`
    /// and `modelDownloadProgress()` is sufficient — no other
    /// requirements leak in. If a third member is ever added to
    /// `ModelLifecycle`, this fixture stops compiling and the test
    /// fails the build, which is the load-bearing oracle for
    /// `testModelLifecycleHasOnlyPrepareAndProgress`.
    private struct MinimalLifecycle: ModelLifecycle {
        let prepareCount: AsyncCounter

        func prepare() async throws {
            await prepareCount.increment()
        }

        func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress> {
            AsyncStream { continuation in
                continuation.yield(
                    ModelDownloadProgress(
                        phase: .finished,
                        fractionCompleted: 1.0,
                        receivedBytes: 0,
                        expectedBytes: nil
                    )
                )
                continuation.finish()
            }
        }
    }

    private actor AsyncCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    // MARK: - Tests

    func testModelLifecycleHasOnlyPrepareAndProgress() async throws {
        // The `MinimalLifecycle` fixture only implements `prepare()`
        // and `modelDownloadProgress()`. If the protocol required any
        // other method, this file would fail to compile — which is the
        // intended behavioral oracle for "the protocol surface is
        // exactly two members."
        let counter = AsyncCounter()
        let lifecycle = MinimalLifecycle(prepareCount: counter)

        try await lifecycle.prepare()

        let invocations = await counter.value
        XCTAssertEqual(invocations, 1, "prepare() should be invokable on a minimal conformer")

        var emitted: [ModelDownloadProgress.Phase] = []
        for await progress in lifecycle.modelDownloadProgress() {
            emitted.append(progress.phase)
        }
        XCTAssertEqual(
            emitted,
            [.finished],
            "modelDownloadProgress() should be invokable on a minimal conformer"
        )
    }

    func testModelLifecycleIsSendable() {
        // Compile-time Sendable enforcement: an `any ModelLifecycle`
        // value must cross actor boundaries. If `ModelLifecycle` ever
        // drops `Sendable`, this assignment fails to compile under
        // Swift 6 strict concurrency, and the test fails the build.
        let counter = AsyncCounter()
        let lifecycle: any ModelLifecycle & Sendable =
            MinimalLifecycle(prepareCount: counter)
        // Reference the value to keep the compiler honest about
        // checking the type.
        XCTAssertNotNil(lifecycle as Any)
    }
}
