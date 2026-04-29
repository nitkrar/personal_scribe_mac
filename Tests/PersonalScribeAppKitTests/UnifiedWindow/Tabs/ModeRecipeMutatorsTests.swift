import XCTest
import PersonalScribeCore
@testable import PersonalScribeAppKit

/// #090 — Pin handling in `ModeRecipeMutators`. Covers the five rules
/// codex flagged: pin set on each transcriber-bearing case, pin
/// cleared on `withRealtime` (kind changes), and pin carried through
/// `withDiarization` (kind preserved across the .transcriber ↔
/// .diarizedTurns transcriber-leg flip).
final class ModeRecipeMutatorsTests: XCTestCase {

    // MARK: - withVoiceModelPin

    func testWithVoiceModelPinSetsPinOnTranscriber() {
        let mode = Self.makeBatchTranscriberMode(descriptorID: nil)

        let pinned = mode.withVoiceModelPin("parakeet-tdt-ctc-110m")

        guard case .transcriber(_, let id) = pinned.processors.first else {
            XCTFail("Expected .transcriber, got \(pinned.processors)")
            return
        }
        XCTAssertEqual(id, "parakeet-tdt-ctc-110m")
    }

    func testWithVoiceModelPinSetsPinOnDiarizedTurnsTranscriberLeg() {
        // Codex flag #2: meeting mode lives in `.diarizedTurns`, not
        // `.transcriber` — the pin mutator must handle that case too.
        let mode = Self.makeDiarizedTurnsMode(transcriberDescriptorID: nil)

        let pinned = mode.withVoiceModelPin("parakeet-tdt-ctc-110m")

        guard case .diarizedTurns(_, _, let id, _) = pinned.processors.first else {
            XCTFail("Expected .diarizedTurns, got \(pinned.processors)")
            return
        }
        XCTAssertEqual(id, "parakeet-tdt-ctc-110m")
    }

    func testWithVoiceModelPinNilClearsExistingPin() {
        let mode = Self.makeBatchTranscriberMode(descriptorID: "parakeet-tdt-0.6b-v2")

        let cleared = mode.withVoiceModelPin(nil)

        guard case .transcriber(_, let id) = cleared.processors.first else {
            XCTFail("Expected .transcriber, got \(cleared.processors)")
            return
        }
        XCTAssertNil(id)
    }

    // MARK: - withRealtime: kind changes → CLEAR pin

    func testWithRealtimeOnClearsTranscriberPin() {
        // .asr → .streamingASR is a kind change, so a pin on the .asr
        // leg becomes incompatible. Toggling realtime drops the pin.
        let mode = Self.makeBatchTranscriberMode(descriptorID: "parakeet-tdt-0.6b-v2")

        let realtime = mode.withRealtime(true)

        guard case .streamingTranscriber(_, let id) = realtime.processors.first else {
            XCTFail("Expected .streamingTranscriber, got \(realtime.processors)")
            return
        }
        XCTAssertNil(id, "Realtime toggle should clear an .asr pin (kind changes to .streamingASR)")
    }

    // MARK: - withDiarization: kind preserved → CARRY pin

    func testWithDiarizationOnCarriesTranscriberPinIntoDiarizedTurns() {
        // .transcriber.descriptorID and .diarizedTurns.transcriberDescriptorID
        // both name the .asr-leg model. Kind preserved → pin carries.
        let mode = Self.makeBatchTranscriberMode(descriptorID: "parakeet-tdt-0.6b-v2")

        let diarized = mode.withDiarization(true)

        guard case .diarizedTurns(_, _, let id, _) = diarized.processors.first else {
            XCTFail("Expected .diarizedTurns, got \(diarized.processors)")
            return
        }
        XCTAssertEqual(id, "parakeet-tdt-0.6b-v2")
    }

    func testWithDiarizationOffCarriesPinFromDiarizedTurnsToTranscriber() {
        let mode = Self.makeDiarizedTurnsMode(
            transcriberDescriptorID: "parakeet-tdt-0.6b-v2"
        )

        let undiarized = mode.withDiarization(false)

        guard case .transcriber(_, let id) = undiarized.processors.first else {
            XCTFail("Expected .transcriber, got \(undiarized.processors)")
            return
        }
        XCTAssertEqual(id, "parakeet-tdt-0.6b-v2")
    }

    // MARK: - Fixtures

    private static func makeBatchTranscriberMode(descriptorID: String?) -> WorkflowMode {
        WorkflowMode(
            id: "test",
            name: "Test",
            pipelineShape: .batch,
            processors: [
                .transcriber(kind: .asr, descriptorID: descriptorID)
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
    }

    private static func makeDiarizedTurnsMode(transcriberDescriptorID: String?) -> WorkflowMode {
        WorkflowMode(
            id: "test-meeting",
            name: "Test Meeting",
            pipelineShape: .batch,
            processors: [
                .diarizedTurns(
                    diarizerKind: .diarization,
                    transcriberKind: .asr,
                    transcriberDescriptorID: transcriberDescriptorID
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )
    }
}
