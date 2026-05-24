import Foundation
import XCTest
@testable import PersonalScribeCore

/// #078.13 — `WorkflowModeValidator` rules. Tests pin each declarative
/// rule independently (per L15) plus end-to-end happy paths for the
/// dictation built-in and a hypothetical meeting recipe.
final class WorkflowModeValidatorTests: XCTestCase {

    // MARK: - Rule-level tests

    func testEmptyProcessorsListIsInvalid() {
        let recipe = WorkflowMode(
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
        let recipe = WorkflowMode(
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
        let recipe = WorkflowMode(
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
            WorkflowMode.dictation,
            availableKinds: [.asr]
        )
    }

    func testValidMeetingRecipePassesValidation() throws {
        // Meeting-style recipe: batch pipeline, diarized turns
        // processor (diarization + ASR), VAD capture, history sink.
        let meeting = WorkflowMode(
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
                    enabled: .setting(PreferenceKeys.vadAutoStopEnabled),
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

    func testStreamingRecipeRequiresStreamingBehavior() {
        let recipe = WorkflowMode(
            id: "streaming",
            name: "Streaming",
            pipelineShape: .streaming,
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
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .streamingShapeRequiresStreamingBehavior
            )
        }
    }

    func testBatchRecipeRejectsPersistedStreamingBehavior() {
        let recipe = WorkflowMode(
            id: "batch-with-streaming-behavior",
            name: "Batch With Streaming Behavior",
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite],
            streamingBehavior: StreamingBehaviorSpec(
                liveCardEnabled: .setting(PreferenceKeys.streamingLiveCardEnabled),
                liveCursorEnabled: .setting(PreferenceKeys.streamingLiveCursorEnabled),
                secondPassEnabled: .setting(PreferenceKeys.streamingSecondPassEnabled)
            )
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                recipe,
                availableKinds: [.asr]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .batchShapeForbidsStreamingBehavior
            )
        }
    }

    // MARK: - #090: per-mode descriptor pinning

    /// A pinned `.transcriber` MUST validate even when its kind is
    /// absent from `availableKinds`. The whole point of #090 is that
    /// pinning bypasses the global-active-descriptor requirement: a
    /// mode that pins its own model should be usable even if the
    /// globally active model for that kind is unset/missing.
    func testPinnedDescriptorBypassesAvailableKindsRequirement() throws {
        let pinned = WorkflowMode(
            id: "pinned-asr",
            name: "Pinned ASR",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: "parakeet-tdt-0.6b-v2"
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        try WorkflowModeValidator.validate(
            pinned,
            availableKinds: [], // nothing globally active
            registeredDescriptors: [BuiltInModelCatalog.parakeetTDT06Bv2]
        )
    }

    /// A pinned `descriptorID` that doesn't reference a registered
    /// descriptor must throw — otherwise the recipe holds a phantom
    /// reference and the user has no signal that their pin is broken.
    func testPinnedDescriptorMustBeRegistered() {
        let pinned = WorkflowMode(
            id: "pinned-missing",
            name: "Pinned Missing",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: "no-such-descriptor"
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                pinned,
                availableKinds: [.asr],
                registeredDescriptors: [BuiltInModelCatalog.parakeetTDT06Bv2]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .pinnedDescriptorNotRegistered(id: "no-such-descriptor")
            )
        }
    }

    /// A pinned `descriptorID` whose descriptor's `kind` doesn't match
    /// the spec's `kind` must throw — pinning a diarization descriptor
    /// to a transcriber spec is incoherent.
    func testPinnedDescriptorKindMustMatchSpecKind() {
        let pinned = WorkflowMode(
            id: "pinned-mismatch",
            name: "Pinned Mismatch",
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.speakerDiarization.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                pinned,
                availableKinds: [.asr],
                registeredDescriptors: [BuiltInModelCatalog.speakerDiarization]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .pinnedDescriptorKindMismatch(
                    id: BuiltInModelCatalog.speakerDiarization.id,
                    expected: .asr,
                    actual: .diarization
                )
            )
        }
    }

    func testLanguageRequiresPinnedDescriptor() {
        let mode = WorkflowMode(
            id: "unpinned-language",
            name: "Unpinned Language",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [.transcriber(kind: .asr)],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: [.asr],
                registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .languageRequiresPinnedDescriptor
            )
        }
    }

    func testLanguageRequiresPinnedDescriptorWithPickerSupport() {
        let mode = WorkflowMode(
            id: "monolingual-language",
            name: "Monolingual Language",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitSmallEn217MB.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        XCTAssertThrowsError(
            try WorkflowModeValidator.validate(
                mode,
                availableKinds: [.asr],
                registeredDescriptors: [BuiltInModelCatalog.whisperKitSmallEn217MB]
            )
        ) { error in
            XCTAssertEqual(
                error as? WorkflowModeValidationError,
                .languageRequiresMultilingualPinnedDescriptor(
                    id: BuiltInModelCatalog.whisperKitSmallEn217MB.id
                )
            )
        }
    }

    func testLanguagePassesForPinnedMultilingualDescriptor() throws {
        let mode = WorkflowMode(
            id: "multilingual-language",
            name: "Multilingual Language",
            language: Parameter<String?>.override("ja"),
            pipelineShape: .batch,
            processors: [
                .transcriber(
                    kind: .asr,
                    descriptorID: BuiltInModelCatalog.whisperKitTiny.id
                )
            ],
            captureControllers: [.manualHotkey],
            outputSinks: [.transcriptHistorySQLite]
        )

        try WorkflowModeValidator.validate(
            mode,
            availableKinds: [],
            registeredDescriptors: [BuiltInModelCatalog.whisperKitTiny]
        )
    }
}
