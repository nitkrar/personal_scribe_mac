import Foundation
import XCTest
import SeshatCore
@testable import SeshatTranscription

final class FluidAudioTranscriberTests: SeshatTranscriptionFilesystemTestCase {
    func testPrepareThrowsModelLoadFailureWhenFluidAudioLoadThrows() async throws {
        let modelRoot = try AppConfig.directory(for: ModelRegistry.parakeetTDT06Bv2)

        try TestModelArtifacts.writeValid(to: modelRoot)

        let recorder = LogRecorder()
        let transcriber = FluidAudioTranscriber(
            downloader: StubModelDownloader(),
            inference: StubInferenceClient(
                loadError: NSError(
                    domain: "CoreMLFake",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Compile failed"]
                )
            ),
            logger: SeshatLogger(category: SeshatLogCategory.transcription),
            logSink: { level, message in
                Task { await recorder.record(level: level, message: message) }
            }
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as SeshatError {
            XCTAssertEqual(error, .modelLoadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let records = await recorder.records
        XCTAssertTrue(records.contains { $0.level == "error" && $0.message.contains("Compile failed") })
    }
}

actor LogRecorder {
    private(set) var records: [(level: String, message: String)] = []

    func record(level: String, message: String) {
        records.append((level: level, message: message))
    }
}
