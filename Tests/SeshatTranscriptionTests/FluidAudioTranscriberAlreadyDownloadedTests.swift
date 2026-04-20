import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberAlreadyDownloadedTests: XCTestCase {
    private static let overrideLock = NSLock()

    private var testRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        Self.overrideLock.lock()
    }

    override func setUp() async throws {
        try await super.setUp()

        testRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        AppConfig.testingBaseDirectoryOverride = testRoot

        let modelRoot = testRoot
            .appendingPathComponent("Seshat", isDirectory: true)
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(BuiltInModelCatalog.parakeetTDT06Bv2.id, isDirectory: true)

        try TestModelArtifacts.writeValid(to: modelRoot)
    }

    override func tearDown() async throws {
        AppConfig.testingBaseDirectoryOverride = nil
        try? FileManager.default.removeItem(at: testRoot)
        try await super.tearDown()
    }

    override func tearDownWithError() throws {
        Self.overrideLock.unlock()
        try super.tearDownWithError()
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
