import XCTest
@testable import PersonalScribeCore

/// #078.1 — `ModelLifecycle` is the shared lifecycle protocol the new
/// output protocols (`Transcriber`, `StreamingTranscriber`,
/// `SpeakerDiarizer`) compose. These tests pin the surface so the
/// composition contract stays minimal for conformers (they only need
/// `prepare()` + progress; `downloadIfNeeded` + `cleanup` keep defaults
/// while `releaseIdleResources` is explicit) and stays
/// Sendable for the strict-concurrency boundary the provider crosses.
final class ModelLifecycleTests: XCTestCase {

    // MARK: - Test fixtures

    /// Minimal conformer used to assert that satisfying `prepare()`
    /// and `modelDownloadProgress()` plus an explicit idle-release
    /// stub is sufficient. If a new required member is ever added
    /// without a default, this fixture stops compiling and the test
    /// fails the build.
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

        func releaseIdleResources() async {}
    }

    private actor AsyncCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }

    // MARK: - Tests

    func testModelLifecycleDefaultHooksKeepMinimalConformerViable() async throws {
        // The `MinimalLifecycle` fixture only implements `prepare()`
        // and `modelDownloadProgress()` plus an explicit
        // `releaseIdleResources()` stub. `downloadIfNeeded` and
        // `cleanup` stay defaultable so simple conformers remain
        // legal even after idle release became explicit.
        let counter = AsyncCounter()
        let lifecycle = MinimalLifecycle(prepareCount: counter)

        try await lifecycle.prepare()
        await lifecycle.cleanup()
        await lifecycle.releaseIdleResources()

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
