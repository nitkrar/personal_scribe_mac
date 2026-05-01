import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.11 — recipe-driven `WorkflowMode` (renamed from
/// `RecipeWorkflowMode` at #078.30b cutover). Tests pin the
/// three-role-list shape, the dictation built-in default, and
/// Codable round-trip.
final class WorkflowModeTests: XCTestCase {

    func testRecipeHoldsThreeRoleLists() {
        // The recipe carries three independently-typed lists per L20.
        // Constructing one with explicit lists and reading them back
        // pins the role separation.
        let recipe = WorkflowMode(
            id: "test-recipe",
            name: "Test Recipe",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertEqual(recipe.processors.count, 1)
        XCTAssertEqual(recipe.captureControllers.count, 1)
        XCTAssertEqual(recipe.outputSinks.count, 1)

        XCTAssertEqual(recipe.processors.first, .transcriber(kind: .asr))
        XCTAssertEqual(recipe.captureControllers.first, .manualHotkey)
        XCTAssertEqual(recipe.outputSinks.first, .transcriptHistorySQLite)
    }

    func testDictationDefaultIsBatchPipelineWithTranscriberAndClipboardSink() {
        let dictation = WorkflowMode.dictation

        XCTAssertEqual(dictation.id, "dictation")
        XCTAssertEqual(dictation.pipelineShape, .batch)
        XCTAssertEqual(dictation.processors, [.transcriber(kind: .asr)])

        // Clipboard sink must be present and reference the central
        // `ClipboardRestoreEnabled` setting via `.setting(...)`.
        let clipboardSink = dictation.outputSinks.first { sink in
            if case .clipboard = sink { return true }
            return false
        }
        XCTAssertNotNil(
            clipboardSink,
            "Dictation must include a clipboard output sink."
        )
        if case .clipboard(let restoreEnabled) = clipboardSink {
            guard case .setting(let key) = restoreEnabled else {
                XCTFail(
                    "Dictation clipboard sink must reference the global `ClipboardRestoreEnabled` setting via `.setting(...)`."
                )
                return
            }
            XCTAssertEqual(key.key, "ClipboardRestoreEnabled")
        }
    }

    func testRecipeCodableRoundTrip() throws {
        let original = WorkflowMode.dictation

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(WorkflowMode.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testLegacyStreamingDecodeWithoutStreamingBehaviorSynthesizesDefaultSettings() throws {
        let decoded = try JSONDecoder().decode(
            WorkflowMode.self,
            from: legacyStreamingJSONWithoutStreamingBehavior()
        )

        XCTAssertEqual(decoded.pipelineShape, .streaming)
        let streamingBehavior = try XCTUnwrap(decoded.streamingBehavior)
        XCTAssertEqual(
            streamingBehavior.liveCardEnabled,
            .setting(PreferenceKeys.streamingLiveCardEnabled)
        )
        XCTAssertEqual(
            streamingBehavior.liveCursorEnabled,
            .setting(PreferenceKeys.streamingLiveCursorEnabled)
        )
        XCTAssertEqual(
            streamingBehavior.secondPassEnabled,
            .setting(PreferenceKeys.streamingSecondPassEnabled)
        )
    }

    func testStreamingDictationPresetSeedsStreamingBehaviorAndDisablesVad() throws {
        let mode = Preset.streamingDictation.materialize(name: "Streaming Dictation")

        XCTAssertEqual(mode.pipelineShape, .streaming)
        XCTAssertEqual(
            mode.streamingBehavior,
            StreamingBehaviorSpec(
                liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
                liveCursorEnabled: .setting(PreferenceKeys.streamingLiveCursorEnabled),
                secondPassEnabled: .setting(PreferenceKeys.streamingSecondPassEnabled)
            )
        )

        let vad = try XCTUnwrap(mode.captureControllers.first { controller in
            if case .vad = controller { return true }
            return false
        })
        guard case .vad(let enabled, _, _, _) = vad else {
            XCTFail("Expected VAD controller")
            return
        }
        XCTAssertEqual(enabled, .override(false))
    }

    // MARK: - #027 — `preset` field

    func testPresetFieldRoundTripsViaCodable() throws {
        let mode = Preset.notes.materialize(name: "My Notes")
        let data = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(WorkflowMode.self, from: data)
        XCTAssertEqual(decoded.preset, .notes)
        XCTAssertEqual(decoded, mode)
    }

    /// Pre-#027 documents have no `preset` key. Decode must succeed and
    /// infer the preset from the persisted `glyph` (L-16 fixed-by-preset).
    func testLegacyDecodeWithoutPresetInfersFromMeetingGlyph() throws {
        let json = legacyJSON(glyph: "person.2.wave.2")
        let decoded = try JSONDecoder().decode(WorkflowMode.self, from: json)
        XCTAssertEqual(decoded.preset, .meeting)
    }

    func testLegacyDecodeWithoutPresetInfersFromStreamingGlyph() throws {
        let json = legacyJSON(glyph: "bolt.horizontal")
        let decoded = try JSONDecoder().decode(WorkflowMode.self, from: json)
        XCTAssertEqual(decoded.preset, .streamingDictation)
    }

    func testLegacyDecodeWithoutPresetOrGlyphFallsBackToDictation() throws {
        // Encoded WITHOUT `preset` and WITHOUT `glyph` — exercises both
        // decodeIfPresent fallbacks at once.
        let json = #"""
        {
          "id": "old-mode",
          "name": "Old",
          "pipelineShape": "batch",
          "processors": [{"type": "transcriber", "kind": "asr"}],
          "captureControllers": [{"type": "manualHotkey"}],
          "outputSinks": [{"type": "transcriptHistorySQLite"}]
        }
        """#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WorkflowMode.self, from: json)
        XCTAssertEqual(decoded.preset, .dictation)
        XCTAssertEqual(decoded.glyph, "mic")
    }

    // MARK: - #027 — id helpers

    func testMakeIDStripsDashesFromUserName() {
        let id = WorkflowMode.makeID(name: "Daily Stand-up", suffix: "abc123")
        // Dash is the separator; a user's "Stand-up" becomes "Standup"
        // so split-on-`-` recovers the cleanName intact.
        XCTAssertEqual(id, "Daily Standup-abc123")
    }

    func testMakeIDFallsBackToModeForEmptyName() {
        let id = WorkflowMode.makeID(name: "  ", suffix: "abc123")
        XCTAssertEqual(id, "mode-abc123")
    }

    func testMakeIDProducesUniqueSuffixesForRepeatedCalls() {
        // Reusing the same name still yields distinct ids — that's the
        // collision-avoidance guarantee the suffix exists for.
        let a = WorkflowMode.makeID(name: "Meeting")
        let b = WorkflowMode.makeID(name: "Meeting")
        XCTAssertNotEqual(a, b)
        XCTAssertTrue(a.hasPrefix("Meeting-"))
        XCTAssertTrue(b.hasPrefix("Meeting-"))
    }

    func testIsLegacyIDMatchesCustomUUIDFormat() {
        XCTAssertTrue(WorkflowMode.isLegacyID("custom-7a3f1c9e-0000"))
        XCTAssertFalse(WorkflowMode.isLegacyID("Meeting-7a3f1c"))
        XCTAssertFalse(WorkflowMode.isLegacyID("dictation"))
    }

    // MARK: - Helpers

    private func legacyJSON(glyph: String) -> Data {
        // Pre-#027 schema: no `preset` key, glyph present, recipe shape
        // matches the meeting preset's processors so the `pipelineShape`
        // stays valid post-validator if a test ever wires one up.
        let body = """
        {
          "id": "legacy-\(glyph)",
          "name": "Legacy",
          "glyph": "\(glyph)",
          "pipelineShape": "batch",
          "processors": [{"type": "transcriber", "kind": "asr"}],
          "captureControllers": [{"type": "manualHotkey"}],
          "outputSinks": [{"type": "transcriptHistorySQLite"}]
        }
        """
        return body.data(using: .utf8)!
    }

    private func legacyStreamingJSONWithoutStreamingBehavior() -> Data {
        let body = #"""
        {
          "id": "legacy-streaming",
          "name": "Legacy Streaming",
          "glyph": "bolt.horizontal",
          "pipelineShape": "streaming",
          "processors": [{"type": "streamingTranscriber", "kind": "streamingASR"}],
          "captureControllers": [{"type": "manualHotkey"}],
          "outputSinks": [{"type": "transcriptHistorySQLite"}]
        }
        """#
        return body.data(using: .utf8)!
    }
}
