import Foundation
import XCTest
import PersonalScribeCore
@testable import PersonalScribeTranscription

final class FluidAudioTranscriberTests: PersonalScribeTranscriptionFilesystemTestCase {
    func testPrepareThrowsModelLoadFailureWhenFluidAudioLoadThrows() async throws {
        let modelRoot = try AppConfig.directory(for: BuiltInModelCatalog.parakeetTDT06Bv2)

        try TestModelArtifacts.writeValid(to: modelRoot)

        let recorder = LogRecorder()
        let transcriber = FluidAudioTranscriber(
            inference: StubInferenceClient(
                loadError: NSError(
                    domain: "CoreMLFake",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Compile failed"]
                )
            ),
            logger: PersonalScribeLogger(category: PersonalScribeLogCategory.transcription),
            logSink: { level, message in
                Task { await recorder.record(level: level, message: message) }
            }
        )

        do {
            try await transcriber.prepare()
            XCTFail("Expected prepare() to throw")
        } catch let error as PersonalScribeError {
            XCTAssertEqual(error, .modelLoadFailure)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        // logSink fires a detached Task to record — poll until the record
        // lands (or bail after ~500 yields) instead of reading once.
        var finalRecords: [(level: String, message: String)] = []
        for _ in 0..<500 {
            finalRecords = await recorder.records
            if finalRecords.contains(where: { $0.level == "error" && $0.message.contains("Compile failed") }) {
                break
            }
            await Task.yield()
        }
        XCTAssertTrue(
            finalRecords.contains { $0.level == "error" && $0.message.contains("Compile failed") },
            "Expected error log containing 'Compile failed'; got: \(finalRecords)"
        )
    }
}

actor LogRecorder {
    private(set) var records: [(level: String, message: String)] = []

    func record(level: String, message: String) {
        records.append((level: level, message: message))
    }
}
