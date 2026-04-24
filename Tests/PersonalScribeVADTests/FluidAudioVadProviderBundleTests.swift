import FluidAudio
import XCTest

@testable import PersonalScribeVAD

/// Guards the Stage A/B invariant that the Silero `.mlmodelc` ships with
/// the app and loads cleanly. A regression in `Package.swift` (typo'd
/// resource path, missing `.copy`, renamed directory) would surface here
/// — `FluidAudioVadProvider.init()` throws `BundledModelError.resourceNotFound`
/// or the subsequent CoreML load returns nil.
final class FluidAudioVadProviderBundleTests: XCTestCase {

    func testFluidAudioVadProviderLoadsBundledModelAndProducesSession() async throws {
        let provider = try FluidAudioVadProvider()
        let handle = await provider.makeSession(silenceThresholdSeconds: 2.5)
        XCTAssertNotNil(
            handle,
            "bundled Silero model must load + produce a session handle on a fresh provider"
        )
    }
}
