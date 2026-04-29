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

    func testProcessorSpecReferencesKindNotDescriptorID() throws {
        // L23 lock: recipes reference `ModelKind`, never a specific
        // descriptor.id. Encoded JSON must carry kind values
        // (matching `ModelKind.RawValue`) — never any field whose
        // value looks like a descriptor identifier.
        let spec = ProcessorSpec.transcriber(kind: .asr)

        let data = try JSONEncoder().encode(spec)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        XCTAssertEqual(json?["kind"] as? String, ModelKind.asr.rawValue)
        XCTAssertNil(
            json?["descriptorID"],
            "ProcessorSpec must not carry a descriptor identifier — recipes late-bind via Kind (L23)."
        )
        XCTAssertNil(
            json?["modelID"],
            "ProcessorSpec must not carry a descriptor identifier — recipes late-bind via Kind (L23)."
        )
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
