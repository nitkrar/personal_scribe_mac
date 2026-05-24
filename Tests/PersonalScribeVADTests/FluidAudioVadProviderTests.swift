import Foundation
import XCTest

@testable import PersonalScribeCore
@testable import PersonalScribeVAD

final class FluidAudioVadProviderTests: XCTestCase {
    func testReleaseIdleResourcesUnloadsLoadedRuntimeAndReloadsOnNextSession() async {
        let loader = RecordingVadSessionFactoryLoader()
        let diagnosticsSink = InMemoryTestSink()
        let provider = FluidAudioVadProvider(
            modelURL: URL(fileURLWithPath: "/tmp/silero-vad.mlmodelc"),
            idleUnloadDelay: .milliseconds(20),
            logger: makeLogger(sink: diagnosticsSink),
            sessionFactoryLoader: loader.load
        )

        let first = await provider.makeSession(silenceThresholdSeconds: 2.5)
        await provider.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        let second = await provider.makeSession(silenceThresholdSeconds: 2.5)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(loader.loadCount, 2)

        let releaseLog = try? await waitForLogMessage(
            in: diagnosticsSink,
            containing: "adapter_idle_release"
        )
        XCTAssertNotNil(releaseLog)
        XCTAssertTrue(releaseLog?.message.contains("descriptorID=silero-vad") == true)
        XCTAssertTrue(releaseLog?.message.contains("adapter=FluidAudioVadProvider") == true)
        XCTAssertTrue(releaseLog?.message.contains("releasedAfterMs=20") == true)
        XCTAssertTrue(releaseLog?.message.contains("hadPrepared=true") == true)
        XCTAssertTrue(releaseLog?.message.contains("hadInFlightPrepare=false") == true)
    }

    func testMakeSessionCancelsPendingIdleUnload() async {
        let loader = RecordingVadSessionFactoryLoader()
        let diagnosticsSink = InMemoryTestSink()
        let provider = FluidAudioVadProvider(
            modelURL: URL(fileURLWithPath: "/tmp/silero-vad.mlmodelc"),
            idleUnloadDelay: .milliseconds(20),
            logger: makeLogger(sink: diagnosticsSink),
            sessionFactoryLoader: loader.load
        )

        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)
        await provider.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(5))
        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)
        try? await Task.sleep(for: .milliseconds(60))
        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)

        XCTAssertEqual(loader.loadCount, 1)
        let releaseLogs = await diagnosticsSink.snapshot().filter {
            $0.message.contains("adapter_idle_release")
        }
        XCTAssertTrue(releaseLogs.isEmpty)
    }
}

private extension FluidAudioVadProviderTests {
    func makeLogger(sink: InMemoryTestSink) -> PersonalScribeLogger {
        PersonalScribeLogger(
            category: PersonalScribeLogCategory.transcription,
            reporter: DiagnosticsReporter(
                sinks: [sink],
                now: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    func waitForLogMessage(
        in sink: InMemoryTestSink,
        containing fragment: String,
        timeout: Duration = .seconds(2)
    ) async throws -> RedactedDiagnosticsEvent {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            if let message = await sink.snapshot().first(where: { $0.message.contains(fragment) }) {
                return message
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTFail("Timed out waiting for diagnostics message containing '\(fragment)'")
        let fallback = await sink.snapshot().first(where: { $0.message.contains(fragment) })
        return try XCTUnwrap(fallback)
    }
}

private final class RecordingVadSessionFactoryLoader: @unchecked Sendable {
    private let lock = NSLock()
    private var loadCountStorage = 0

    func load(from _: URL) -> VadSessionFactory? {
        lock.lock()
        loadCountStorage += 1
        lock.unlock()

        return { _ in
            VadSessionHandle { _ in nil }
        }
    }

    var loadCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return loadCountStorage
    }
}
