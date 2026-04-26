import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.13 — `WorkflowModeValidator` rules. Tests pin each declarative
/// rule independently (per L15) plus end-to-end happy paths for the
/// dictation built-in and a hypothetical meeting recipe.
final class WorkflowModeValidatorTests: XCTestCase {

    // MARK: - Rule-level tests

    func testEmptyProcessorsListIsInvalid() {
        let recipe = RecipeWorkflowMode(
            id: "empty",
            name: "Empty",
            pipelineShape: .batch,
            processors: [],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                recipe,
                availableKinds: [.asr]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .emptyProcessors
            )
        }
    }

    func testStreamingTranscriberRequiresStreamingShape() {
        // Streaming processor declared with batch shape — must fail.
        let recipe = RecipeWorkflowMode(
            id: "mismatched",
            name: "Mismatched",
            pipelineShape: .batch,
            processors: [.streamingTranscriber(kind: .streamingASR)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                recipe,
                availableKinds: [.streamingASR]
            )
        ) { error in
            guard case .streamingShapeMismatch = error as? WorkflowModeValidationError else {
                XCTFail("Expected .streamingShapeMismatch, got \(error)")
                return
            }
        }
    }

    func testDiarizedTurnsRequiresAsrOrStreamingAsrTranscriberKind() {
        // Diarized turns with a non-ASR transcriber kind (e.g. .vad)
        // must fail with the dedicated error.
        let recipe = RecipeWorkflowMode(
            id: "bad-diarized",
            name: "Bad Diarized",
            pipelineShape: .batch,
            processors: [
                .diarizedTurns(
                    diarizerKind: .diarization,
                    transcriberKind: .vad
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                recipe,
                availableKinds: [.diarization, .vad, .asr]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .diarizedTurnsRequiresAsrTranscriberKind(provided: .vad)
            )
        }
    }

    // MARK: - Happy-path tests

    func testValidDictationRecipePassesValidation() throws {
        try WorkflowModeValidator.validate(
            RecipeWorkflowMode.dictation,
            availableKinds: [.asr]
        )
    }

    func testValidMeetingRecipePassesValidation() throws {
        // Meeting-style recipe: batch pipeline, diarized turns
        // processor (diarization + ASR), VAD capture, history sink.
        let meeting = RecipeWorkflowMode(
            id: "meeting",
            name: "Meeting",
            pipelineShape: .batch,
            processors: [
                .diarizedTurns(
                    diarizerKind: .diarization,
                    transcriberKind: .asr
                )
            ],
            captureControllers: [
                .vad(
                    silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                    showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
                    showAutoStoppedNotification: .setting(
                        PreferenceKeys.vadShowAutoStoppedNotification
                    )
                )
            ],
            outputSinks: [.transcriptHistorySQLite]
        )

        try WorkflowModeValidator.validate(
            meeting,
            availableKinds: [.diarization, .asr]
        )
    }
}
