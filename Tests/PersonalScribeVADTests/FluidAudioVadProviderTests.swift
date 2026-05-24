import Foundation
import XCTest

@testable import PersonalScribeVAD

final class FluidAudioVadProviderTests: XCTestCase {
    func testReleaseIdleResourcesUnloadsLoadedRuntimeAndReloadsOnNextSession() async {
        let loader = RecordingVadSessionFactoryLoader()
        let provider = FluidAudioVadProvider(
            modelURL: URL(fileURLWithPath: "/tmp/silero-vad.mlmodelc"),
            idleUnloadDelay: .milliseconds(20),
            sessionFactoryLoader: loader.load
        )

        let first = await provider.makeSession(silenceThresholdSeconds: 2.5)
        await provider.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(60))
        let second = await provider.makeSession(silenceThresholdSeconds: 2.5)

        XCTAssertNotNil(first)
        XCTAssertNotNil(second)
        XCTAssertEqual(loader.loadCount, 2)
    }

    func testMakeSessionCancelsPendingIdleUnload() async {
        let loader = RecordingVadSessionFactoryLoader()
        let provider = FluidAudioVadProvider(
            modelURL: URL(fileURLWithPath: "/tmp/silero-vad.mlmodelc"),
            idleUnloadDelay: .milliseconds(20),
            sessionFactoryLoader: loader.load
        )

        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)
        await provider.releaseIdleResources()
        try? await Task.sleep(for: .milliseconds(5))
        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)
        try? await Task.sleep(for: .milliseconds(60))
        _ = await provider.makeSession(silenceThresholdSeconds: 2.5)

        XCTAssertEqual(loader.loadCount, 1)
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
