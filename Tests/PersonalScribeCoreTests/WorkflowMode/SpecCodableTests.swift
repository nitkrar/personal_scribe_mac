import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.10 — `ProcessorSpec`, `CaptureControllerSpec`, `OutputSinkSpec`
/// Codable round-trip + Kind-not-descriptor-ID assertion (L23).
final class SpecCodableTests: XCTestCase {

    // MARK: - ProcessorSpec

    func testProcessorSpecDiarizedTurnsRoundTrip() throws {
        let original = ProcessorSpec.diarizedTurns(
            diarizerKind: .diarization,
            transcriberKind: .asr
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ProcessorSpec.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testProcessorSpecOmitsDescriptorIDWhenUnpinned() throws {
        // #090: unpinned processors (default `descriptorID: nil`) MUST
        // round-trip without emitting a `descriptorID` /
        // `transcriberDescriptorID` field, so existing
        // `workflow-modes.json` documents written before #090 round-trip
        // unchanged. Late-bind to the globally-active descriptor (per
        // `ActiveModelService.activeDescriptor(for:)`) remains the
        // default behavior when the field is absent.
        let cases: [(ProcessorSpec, [String])] = [
            (.transcriber(kind: .asr), ["descriptorID"]),
            (.streamingTranscriber(kind: .streamingASR), ["descriptorID"]),
            (
                .diarizedTurns(diarizerKind: .diarization, transcriberKind: .asr),
                ["transcriberDescriptorID"]
            ),
        ]
        for (spec, forbiddenKeys) in cases {
            let data = try JSONEncoder().encode(spec)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            for key in forbiddenKeys {
                XCTAssertNil(
                    json?[key],
                    "Unpinned \(spec) must omit \(key) on encode."
                )
            }
        }
    }

    func testProcessorSpecRoundTripsDescriptorIDOverride() throws {
        // #090: a pinned processor (non-nil `descriptorID`) MUST encode
        // its descriptor id and decode back to the same pin, so the
        // user's per-mode model selection survives Codable round-trip
        // through `WorkflowModeDocument` storage.
        let cases: [ProcessorSpec] = [
            .transcriber(kind: .asr, descriptorID: "parakeet-tdt-0.6b-v2"),
            .streamingTranscriber(
                kind: .streamingASR,
                descriptorID: "parakeet-realtime-eou-120m-160ms"
            ),
            .diarizedTurns(
                diarizerKind: .diarization,
                transcriberKind: .asr,
                transcriberDescriptorID: "parakeet-tdt-0.6b-v2"
            ),
        ]
        for original in cases {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(ProcessorSpec.self, from: data)
            XCTAssertEqual(decoded, original, "Pinned spec did not round-trip: \(original)")
        }
    }

    // MARK: - CaptureControllerSpec

    func testCaptureControllerSpecVadCarriesParameters() throws {
        let original = CaptureControllerSpec.vad(
            enabled: .override(true),
            silenceThreshold: .setting(
                SettingKey<TimeInterval>(
                    key: "VadSilenceDurationSeconds",
                    default: 5.0
                )
            ),
            showWarning: .override(true),
            showAutoStoppedNotification: .override(false)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(
            CaptureControllerSpec.self,
            from: data
        )

        guard case .vad(let enabled, let threshold, let warning, let notification) = decoded else {
            XCTFail("Expected .vad case, got \(decoded)")
            return
        }
        XCTAssertEqual(enabled, .override(true))
        guard case .setting(let key) = threshold else {
            XCTFail("silenceThreshold should round-trip as .setting")
            return
        }
        XCTAssertEqual(key.key, "VadSilenceDurationSeconds")
        XCTAssertEqual(key.default, 5.0, accuracy: 0.0001)
        XCTAssertEqual(warning, .override(true))
        XCTAssertEqual(notification, .override(false))
    }

    // MARK: - OutputSinkSpec

    func testStreamingBehaviorSpecRoundTripsParameters() throws {
        let original = StreamingBehaviorSpec(
            liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
            liveCursorEnabled: .override(true),
            secondPassEnabled: .override(false)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(StreamingBehaviorSpec.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testOutputSinkSpecClipboardCarriesRestoreParameter() throws {
        let original = OutputSinkSpec.clipboard(
            restoreEnabled: .override(false)
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(OutputSinkSpec.self, from: data)

        guard case .clipboard(let restoreEnabled) = decoded else {
            XCTFail("Expected .clipboard case, got \(decoded)")
            return
        }
        XCTAssertEqual(restoreEnabled, .override(false))
    }
}
