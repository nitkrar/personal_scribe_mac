import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberAlreadyDownloadedTests: XCTestCase {
    private var testRoot: URL!

    override func setUp() async throws {
        try await super.setUp()

        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        SeshatConfig.testingBaseDirectoryOverride = testRoot

        let modelRoot = testRoot
            .appendingPathComponent("Seshat", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent("parakeet-tdt-0.6b-v2", isDirectory: true)

        try TestModelArtifacts.writeValid(to: modelRoot)
    }

    override func tearDown() async throws {
        SeshatConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }

    func testPrepareSkipsDownloadWhenModelAlreadyOnDisk() async throws {
        let recordingSession = RecordingURLSession()
        let downloader = StubModelDownloader(recordingSession: recordingSession)
        let transcriber = FluidAudioTranscriber(
            downloader: downloader,
            inference: StubInferenceClient(loadError: nil)
        )

        try await transcriber.prepare()

        let requests = await recordingSession.requests
        XCTAssertTrue(requests.isEmpty)
    }
}
