# Plan: #078 — Adapter layer for non-Parakeet model families

**Goal**: Land the locked design at `plans/078_adapter_layer/DESIGN.md` v2 — three role-typed output protocols (`Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`), four FluidAudio adapters, recipe-driven `WorkflowMode` composition, eager-bound `Parameter<T>` cascade, recipe-driven orchestrator, and Settings-toggle-as-recipe-builder migration.
**Architecture**: Engine→adapter dispatch lives only in `ModelBoundProcessorProvider` (L24). `ModelLifecycle`-composed protocols (L13). Recipes reference `ModelKind`, late-bound at session start via `ActiveModelService.activeDescriptor(for:)` and frozen for the in-flight session (L25). Fusion processor `DiarizedTurnTranscriptionProcessor` slices audio per finalized turn, drops gaps, ASRs overlap zones end-to-end (L26).
**Tech Stack**: Swift 6 (strict concurrency), SPM, FluidAudio SDK, XCTest. Commit tag prefix `phase-3 step #078.N` per project convention.

## Conventions

- Each step is **2–5 minutes of focused work**, test-first per Ninimma TDD.
- Test + impl land in the **same commit** (TDD discipline).
- Build cadence per sub-step: `swift build --build-tests`. Filtered `swift test --filter <Suite>` at staged-changes checkpoints.
- Full-suite `swift test` only at end-of-phase gates (A, B, C, D, E, F, G, H closure).
- No backward-compat aliases (`Renamed<X>` typealiases) — rename + reshape per project rule.
- ⚠️ marks steps that need **runtime verification** (DMG build, manual test) before proceeding.
- Module locations: target names per the rename batch already landed (`Transcriber`, `WorkflowMode`, `PipelineShape`, `PipelineStepID`).

---

## Phase A — Core protocols + types (`PersonalScribeCore`)

Goal of Phase A: land the new protocol surface and the descriptor reshape. Existing parakeet adapter still conforms to the kept `Transcriber` protocol; nothing breaks.

### #078.1 — `ModelLifecycle` protocol extracted
- [ ] **Goal**: Pull `prepare()` + `modelDownloadProgress()` out of `Transcriber` into a separate protocol per L3/L13.
- **Files**: `Sources/PersonalScribeCore/Transcription/ModelLifecycle.swift` (new); `Sources/PersonalScribeCore/Protocols.swift` (`Transcriber: ModelLifecycle`).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/ModelLifecycleTests.swift` — `testTranscriberConformsToModelLifecycle`, `testModelLifecycleHasOnlyPrepareAndProgress`.
- **Depends on**: none.

### #078.2 — `TranscriberCapabilities` struct
- [ ] **Goal**: 4-field `Bool` struct (`providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`) per synthesis #1.
- **Files**: `Sources/PersonalScribeCore/Transcription/TranscriberCapabilities.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/TranscriberCapabilitiesTests.swift` — `testAllFieldsDefaultFalse`, `testParakeetCapabilitiesEnableAllFour`, `testQwenCapabilitiesAreTextOnly`.
- **Depends on**: none.

### #078.3 — `Transcriber` gains `capabilities`; `TranscriptionResult` gains optional metadata
- [ ] **Goal**: Extend `Transcriber` with `var capabilities: TranscriberCapabilities { get }`. Extend `TranscriptionResult` with optional `confidence: Float?`, `tokenTimings: [TokenTiming]?`, `performanceMetrics: TranscriberPerformanceMetrics?`, `ctcDetectedTerms: [String]?`, `ctcAppliedTerms: [String]?` per L11.
- **Files**: `Sources/PersonalScribeCore/Protocols.swift`; `Sources/PersonalScribeCore/TranscriptionResult.swift`; new `Sources/PersonalScribeCore/Transcription/TokenTiming.swift`; new `Sources/PersonalScribeCore/Transcription/TranscriberPerformanceMetrics.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/TranscriptionResultMetadataTests.swift` — `testTranscriptionResultDefaultsAllOptionalMetadataNil`, `testTokenTimingRoundTripsStartEndConfidence`.
- **Depends on**: #078.1, #078.2.

### #078.4 — `StreamingTranscriber` protocol
- [ ] **Goal**: `protocol StreamingTranscriber: ModelLifecycle` with `func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error>` + `var capabilities: TranscriberCapabilities`. Event enum cases: `.partial(text:)`, `.endOfUtterance(text:)`, `.finalized(TranscriptionResult)`.
- **Files**: `Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift` (new); `Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/StreamingTranscriberContractTests.swift` — `testStreamingEventCasesAreExhaustive`, `testStreamingTranscriberComposesModelLifecycle`.
- **Depends on**: #078.1, #078.2.

### #078.5 — `SpeakerDiarizer` protocol + event type
- [ ] **Goal**: `protocol SpeakerDiarizer: ModelLifecycle` with `func diarize(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<SpeakerDiarizationEvent, Error>`. Event mirrors FluidAudio's update-oriented shape (L10): `.update(provisional: [SpeakerTurn], finalized: [SpeakerTurn])`, `.terminal([SpeakerTurn])`. `SpeakerTurn { speakerID: String, start: Duration, end: Duration }`. Core extension provides batch convenience `diarize(_ audio: PCMBuffer)` that wraps a one-buffer stream.
- **Files**: `Sources/PersonalScribeCore/Transcription/SpeakerDiarizer.swift` (new); `Sources/PersonalScribeCore/Transcription/SpeakerDiarizationEvent.swift` (new); `Sources/PersonalScribeCore/Transcription/SpeakerTurn.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/SpeakerDiarizerContractTests.swift` — `testSpeakerTurnPreservesIDAndDurations`, `testDiarizationEventCarriesProvisionalAndFinalizedSeparately`, `testBatchConvenienceWrapsSingleBufferStream`.
- **Depends on**: #078.1.

### #078.6 — `TranscriptionEngine.kind` computed; remove stored `ModelDescriptor.kind`
- [ ] **Goal**: Add `var kind: ModelKind` on `TranscriptionEngine` mapping `.parakeetTDT → .asr`, `.qwen3ASR → .asr`, `.parakeetEOU → .streamingASR`, `.diarization → .diarization` per L2. Remove stored `kind` from `ModelDescriptor`. Catalog descriptors stop passing `kind:`. **Codable migration**: `ModelDescriptor+Codable.swift` ignores legacy `kind` field on decode (back-compat for any persisted descriptor blobs); never encodes `kind`.
- **Files**: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`; `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor+Codable.swift`; `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`; `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/Models/TranscriptionEngineKindTests.swift` — `testParakeetTDTMapsToAsr`, `testParakeetEOUMapsToStreamingASR`, `testQwen3ASRMapsToAsr`, `testDiarizationMapsToDiarization`. `Tests/PersonalScribeCoreTests/Models/ModelDescriptorCodableLegacyKindTests.swift` — `testDecodeWithLegacyKindFieldDropsItSilently`, `testEncodeOmitsKindField`.
- **Depends on**: nothing (parallel to #078.1–#078.5).
- **Migration callout**: persisted `Active*` UserDefaults blobs continue to decode; legacy `kind` is dropped silently.

### Phase A close
- [ ] Run `swift test --filter PersonalScribeCoreTests` from canonical repo path. All green.

---

## Phase B — Mode types (`PersonalScribeCore/WorkflowMode/`)

Goal: add the recipe shape + Codable schema + validator, alongside today's `WorkflowMode` (which gets reshaped, not aliased).

### #078.7 — `SettingKey<Value>` introduced
- [ ] **Goal**: Add `SettingKey<Value: Codable & Sendable>` thin wrapper around `String` key + default. Declared in core; conforms `Sendable`. Built atop existing `Preference<Value>` mechanism (resolution via `PreferenceCodec`). Per round-1 review suggestion #3.
- **Files**: `Sources/PersonalScribeCore/Preferences/SettingKey.swift` (new); `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift` (new — central registry of all known keys).
- **Tests**: `Tests/PersonalScribeCoreTests/Preferences/SettingKeyTests.swift` — `testSettingKeyResolvesFromUserDefaults`, `testSettingKeyFallsBackToDefaultWhenAbsent`, `testRegistryIncludesVadSilenceThresholdKey`.
- **Depends on**: none.

### #078.8 — `Parameter<Value>` enum + `ParameterResolver`
- [ ] **Goal**: `enum Parameter<Value: Codable & Sendable> { case setting(SettingKey<Value>), override(Value) }`. Codable as `{source: "setting", key: "..."}` or `{source: "override", value: ...}` per L22. `ParameterResolver` is the single resolution site, eager at piece-construction.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/ParameterResolver.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/ParameterCodableTests.swift` — `testSettingCaseEncodesSourceAndKey`, `testOverrideCaseEncodesSourceAndValue`, `testRoundTripPreservesCase`. `Tests/PersonalScribeCoreTests/WorkflowMode/ParameterResolverTests.swift` — `testOverrideWinsOverSetting`, `testSettingFallsBackToHardcodedDefault`, `testResolverReturnsValueAtCallTime`.
- **Depends on**: #078.7.

### #078.9 — `ProcessorSpec`, `CaptureControllerSpec`, `OutputSinkSpec`
- [ ] **Goal**: Three role-specific `enum` spec types per L20. `ProcessorSpec` cases: `.transcriber(kind: ModelKind)`, `.streamingTranscriber(kind: ModelKind)`, `.diarizedTurns(diarizerKind: ModelKind, transcriberKind: ModelKind)`. `CaptureControllerSpec` cases: `.vad(silenceThreshold: Parameter<TimeInterval>, showWarning: Parameter<Bool>, showAutoStoppedNotification: Parameter<Bool>)`, `.manualHotkey`. `OutputSinkSpec` cases: `.clipboard(restoreEnabled: Parameter<Bool>)`, `.frontmostPaste`, `.transcriptHistorySQLite`. All Codable, Equatable, Sendable.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/SpecCodableTests.swift` — `testProcessorSpecDiarizedTurnsRoundTrip`, `testCaptureControllerSpecVadCarriesParameters`, `testOutputSinkSpecClipboardCarriesRestoreParameter`. `testProcessorSpecReferencesKindNotDescriptorID` (asserts no `descriptorID` field — L23).
- **Depends on**: #078.8.

### #078.10 — `WorkflowMode` reshape
- [ ] **Goal**: Replace the legacy `WorkflowMode { id, name, voiceModelID, aiModelID, systemPrompt }` with the recipe shape: `WorkflowMode { id, name, pipelineShape: PipelineShape, processors: [ProcessorSpec], captureControllers: [CaptureControllerSpec], outputSinks: [OutputSinkSpec] }`. Delete `voiceModelID`, `aiModelID`, `systemPrompt` (L1 — descriptor identity is canonical, modes refer by Kind).
- **Files**: `Sources/PersonalScribeCore/WorkflowMode.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowModeTests.swift` (rewrite) — `testWorkflowModeHoldsThreeRoleLists`, `testDictationDefaultIsBatchPipelineWithTranscriberAndClipboardSink`, `testWorkflowModeCodableRoundTrip`.
- **Depends on**: #078.9.
- **Note**: This breaks `PipelineContextSnapshot.activeMode`, `PostProcessingContext.activeMode`, `StatusItemController.modes`, `ModesTabViewModel`, `ServiceBackedActiveModeProvider` — fix in Phase F orchestrator and Phase H UI catch-up. Until those land, `swift build` fails outside the core target. Build green is restored at the end of Phase G.

### #078.11 — `WorkflowModeDocument` Codable schema
- [ ] **Goal**: `struct WorkflowModeDocument: Codable { schemaVersion: Int (=1), activeModeID: String?, customModes: [WorkflowMode] }` per synthesis #5.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeDocumentTests.swift` — `testDocumentRoundTripPreservesSchemaVersion`, `testDocumentDefaultsActiveModeIDToNil`, `testDocumentDecodesEmptyCustomModesAsEmptyArray`.
- **Depends on**: #078.10.

### #078.12 — `WorkflowModeValidator`
- [ ] **Goal**: Pure-function `enum WorkflowModeValidator` with `static func validate(_:) throws`. Rules per L15: at least one processor; processor `.streamingTranscriber` requires `pipelineShape == .streaming`; processor `.diarizedTurns` requires both Kinds enabled in the active model service or fails with `WorkflowModeValidationError.kindUnavailable`; `.diarizedTurns(transcriberKind:)` must be `.asr` or `.streamingASR`; if `.streaming` shape, exactly one streaming processor. Per round-1 review suggestion: rules live as a `static func` (not closures — preserves Codable), centralized.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidationError.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeValidatorTests.swift` — `testEmptyProcessorsListIsInvalid`, `testStreamingTranscriberRequiresStreamingShape`, `testDiarizedTurnsRequiresAsrOrStreamingAsrTranscriberKind`, `testValidDictationRecipePassesValidation`, `testValidMeetingRecipePassesValidation`.
- **Depends on**: #078.10.

### Phase B close
- [ ] `swift build --build-tests` (will still fail outside core; expected). `swift test --filter PersonalScribeCoreTests` green.

---

## Phase C — Provider rename + typed accessors (`PersonalScribeSession`)

Goal: rename `ModelBoundTranscriberProvider → ModelBoundProcessorProvider` with typed accessors and shared per-descriptor cache. Engine→adapter dispatch consolidated here per L7/L24.

### #078.13 — Define `ModelBoundProcessorProviding` protocol
- [ ] **Goal**: `protocol ModelBoundProcessorProviding: Sendable { func transcriber(for: ModelDescriptor) throws -> any Transcriber; func streamingTranscriber(for: ModelDescriptor) throws -> any StreamingTranscriber; func diarizer(for: ModelDescriptor) throws -> any SpeakerDiarizer; func isDownloaded(_:) -> Bool; func download(_:progress:) async throws; func removeDownloadedFiles(_:) throws }`. Wrong-accessor calls throw `ModelSelectionError.unsupportedKind`.
- **Files**: `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProviding.swift` (new); delete `ModelBoundTranscriberProviding.swift`.
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProvidingTests.swift` — `testProtocolExposesThreeTypedAccessors`, `testProtocolKeepsSharedDownloadAndIsDownloaded`.
- **Depends on**: Phase A done.

### #078.14 — `AdapterRecord` + shared cache infrastructure
- [ ] **Goal**: Internal `AdapterRecord` struct holds the optional `Transcriber` / `StreamingTranscriber` / `SpeakerDiarizer` adapter for one descriptor. Provider holds `[descriptorID: AdapterRecord]` keyed dict; `isDownloaded`, `download`, `removeDownloadedFiles` route via the record's `ModelLifecycle` so the lifecycle path stays single per L7.
- **Files**: `Sources/PersonalScribeSession/Models/Selection/AdapterRecord.swift` (new — internal).
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/AdapterRecordTests.swift` — `testRecordHoldsThreeOptionalsForOneDescriptor`, `testRecordExposesUniformLifecycleAcrossThreeAdapterTypes`.
- **Depends on**: #078.13.

### #078.15 — Rename + reshape `ModelBoundTranscriberProvider → ModelBoundProcessorProvider`
- [ ] **Goal**: Rename file + class. Implement three typed accessors. `switch descriptor.engine` is the **only** dispatch (L24). `.parakeetTDT → FluidAudioParakeetTranscriberAdapter`, `.qwen3ASR → FluidAudioQwenTranscriberAdapter`, `.parakeetEOU → FluidAudioStreamingTranscriberAdapter`, `.diarization → FluidAudioOfflineDiarizerAdapter`. Wrong accessor for engine throws `unsupportedKind`. Adapters are stubs in this step (filled in Phase D).
- **Files**: `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` (renamed from `ModelBoundTranscriberProvider.swift`).
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProviderTests.swift` — `testTranscriberAccessorThrowsForStreamingEngine`, `testStreamingTranscriberAccessorThrowsForBatchEngine`, `testDiarizerAccessorThrowsForAsrEngine`, `testSameDescriptorReturnsSharedCacheRecord`, `testRemoveDownloadedFilesEvictsAllAdapterTypes`.
- **Depends on**: #078.14.

### #078.16 — Update all callsites of `ModelBoundTranscriberProviding`
- [ ] **Goal**: Replace every `any ModelBoundTranscriberProviding` and `ModelBoundTranscriberProvider` reference with the new protocol/class. `AppComposition.swift`, `SessionPipelineOrchestrator.swift`, `SessionCoordinator.swift`, test fakes.
- **Files**: `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`; `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` (call-site only); `Sources/PersonalScribeSession/SessionCoordinator.swift`; test fakes under `Tests/PersonalScribeSessionTests/`.
- **Tests**: existing tests must keep passing (no new tests; this is a mechanical rename of references).
- **Depends on**: #078.15.
- **⚠️ Build gate**: `swift build --build-tests` should compile cleanly through `PersonalScribeSession` after this step (orchestrator still uses `transcriber(for:)` only; broader recipe wiring lands Phase G).

### Phase C close
- [ ] `swift test --filter PersonalScribeSessionTests/Models/Selection` green.

---

## Phase D — Adapters (`PersonalScribeTranscription/Adapters/`)

Goal: four FluidAudio adapters, one per manager class (L4). Existing `ModelAwareFluidAudioTranscriber` is renamed/relocated into the parakeet adapter; `FluidAudioRuntimeVariant` collapses into a parakeet-internal detail (L4 consequence).

### #078.17 — `FluidAudioParakeetTranscriberAdapter`
- [ ] **Goal**: Rename `ModelAwareFluidAudioTranscriber` → `FluidAudioParakeetTranscriberAdapter`, move into `Sources/PersonalScribeTranscription/Adapters/`. Conforms `Transcriber`. Declares `static let capabilities = TranscriberCapabilities(providesTokenTimings: true, providesConfidence: true, providesPerformanceMetrics: true, providesCustomVocabulary: true)`. Maps `ASRResult` → extended `TranscriptionResult` with all metadata fields populated. Inline `FluidAudioRuntimeVariant` as a parakeet-internal detail; delete the cross-family enum file.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` (new from rename); delete `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift`, `Sources/PersonalScribeTranscription/Models/Selection/FluidAudioRuntimeVariant.swift`, `Sources/PersonalScribeTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift`.
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioParakeetTranscriberAdapterTests.swift` — `testCapabilitiesDeclareAllFourTrue`, `testTranscribeReturnsResultWithTokenTimingsPopulated`, `testTranscribeReturnsConfidenceFromAsrResult`. Existing `FluidAudioTranscriberTests.swift`, `PrepareIdempotenceTests.swift`, etc. update to new class name.
- **Depends on**: Phase C done.

### #078.18 — `FluidAudioQwenTranscriberAdapter`
- [ ] **Goal**: New adapter wrapping `Qwen3AsrManager`. Conforms `Transcriber`. `capabilities = TranscriberCapabilities(.... all false)` per investigation evidence (Qwen3 returns plain `String`). Maps `String → TranscriptionResult(text: ..., audioDuration: known, processingDuration: measured)`; metadata fields stay `nil`. `prepare()` delegates to FluidAudio's `Qwen3AsrManager.initialize` after model files are present.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioQwenTranscriberAdapterTests.swift` — `testCapabilitiesAreAllFalse`, `testTranscribeReturnsTextOnlyResultWithNilMetadata`, `testPrepareLoadsModelFromDescriptorDirectory`.
- **Depends on**: #078.17.

### #078.19 — `FluidAudioStreamingTranscriberAdapter`
- [ ] **Goal**: New adapter wrapping `StreamingEouAsrManager`. Conforms `StreamingTranscriber`. Bridges FluidAudio's `partial`/`EOU` callback API to `AsyncThrowingStream<StreamingTranscriptionEvent, Error>`. Per-chunk audio fed via `process(audioBuffer:)`; `partial` callbacks emit `.partial(text:)`, EOU callbacks emit `.endOfUtterance(text:)`, `finish()` emits `.finalized(...)` and terminates the stream. `capabilities = TranscriberCapabilities(... all false)` for now — streaming EOU exposes `String` only.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift` — `testPartialCallbackEmitsPartialEvent`, `testEouCallbackEmitsEndOfUtteranceEvent`, `testFinishEmitsFinalizedEventAndTerminates`, `testStreamErrorTerminatesEventStream`.
- **Depends on**: #078.17.

### #078.20 — `FluidAudioOfflineDiarizerAdapter`
- [ ] **Goal**: New adapter wrapping `OfflineDiarizerManager` directly (NOT via FluidAudio's `Diarizer` protocol — confirmed by review-2: `OfflineDiarizerManager` does not conform). Conforms our `SpeakerDiarizer`. Degenerate streaming: buffers all incoming audio, calls `process(audio:)` on stream end, emits one `.terminal([SpeakerTurn])` event with all turns. Maps FluidAudio `TimedSpeakerSegment` → our `SpeakerTurn`.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioOfflineDiarizerAdapterTests.swift` — `testDegenerateStreamingEmitsSingleTerminalEvent`, `testTerminalEventCarriesAllTurnsFromOfflineManager`, `testEmptyAudioStreamProducesEmptyTerminalEvent`.
- **Depends on**: #078.17.

### Phase D close
- [ ] ⚠️ **Runtime verification**: download Parakeet model, record short dictation via existing pipeline (still parakeet-only at this point); confirm transcript still appears on clipboard. Confirms no regression in #078.17 rename.

---

## Phase E — Fusion processor (`PersonalScribeSession/Pipeline/Processors/`)

Goal: shared `DiarizedTurnTranscriptionProcessor` per L26. Composable piece (option b from BRIEF Q2).

### #078.21 — `Processor` role-protocol
- [ ] **Goal**: Tiny role protocol `protocol Processor: Sendable { associatedtype Output; func process(audioStream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<Output, Error> }` per L20.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/Processor.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/ProcessorContractTests.swift` — `testProcessorAssociatedTypeOutputIsRequired`.
- **Depends on**: Phase A done.

### #078.22 — Audio-slice helper
- [ ] **Goal**: Pure-function helper `func slice(_ pcmBuffer: PCMBuffer, from: Duration, to: Duration) -> PCMBuffer`. Sample-accurate based on the buffer's sample rate. Used by the fusion processor to send per-turn audio to the batch transcriber.
- **Files**: `Sources/PersonalScribeCore/Audio/PCMBufferSlicing.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Audio/PCMBufferSlicingTests.swift` — `testSliceReturnsSampleAccurateRange`, `testSliceClampsToBufferBounds`, `testSliceOfZeroDurationReturnsEmptyBuffer`.
- **Depends on**: none.

### #078.23 — `DiarizedTurnTranscriptionProcessor` — finalize-only path
- [ ] **Goal**: Processor consumes audio + fans it into both the `SpeakerDiarizer` (forwarded as-is) and an internal accumulator. On `.terminal([turns])` (or `.update(finalized: …)`), for each finalized turn: slice the accumulated audio per turn timestamps, send to the bound `Transcriber` via batch `transcribe(_:)`. Emits `(speakerID, TranscriptionResult)` pairs. Implements L26 contract: gaps drop (no transcribe call for audio not covered by a finalized turn); overlap zones ASR each turn end-to-end (slicing per turn includes the overlap range); provisional turns ignored (only finalized trigger ASR).
- **Files**: `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTurnTranscriptionProcessor.swift` (new); `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTranscript.swift` (new — output payload).
- **Tests**: `Tests/PersonalScribeSessionTests/Pipeline/Processors/DiarizedTurnTranscriptionProcessorTests.swift`:
  - `testFinalizedTurnsTriggerOnePerSpeakerTranscribeCall` (FakeDiarizer emits 2 finalized turns → FakeTranscriber recorded 2 calls)
  - `testGapBetweenTurnsIsNotTranscribed` (3rd region of audio outside any turn → 0 extra transcribe calls)
  - `testOverlapZoneIsTranscribedTwiceEndToEnd` (turn A 0–5s, turn B 3–8s → 2 calls, slice for A is 0–5s, slice for B is 3–8s, both include the 3–5s overlap)
  - `testProvisionalTurnsAreNotTranscribed` (FakeDiarizer emits provisional → FakeTranscriber recorded 0 calls; only finalized triggers)
  - `testDiarizerErrorTerminatesOutputStream`
  - `testTranscriberErrorOnOneTurnDoesNotPreventOtherTurns` (per-turn isolation; per L26 garbled-but-captured > silent loss)
- **Depends on**: #078.21, #078.22, #078.20, #078.17.

### Phase E close
- [ ] `swift test --filter PersonalScribeSessionTests/Pipeline/Processors` green.

---

## Phase F — Registry + migration (`PersonalScribeSession/WorkflowMode/`)

Goal: `WorkflowModeRegistry` (L21) loads/saves `WorkflowModeDocument`, owns active-mode state, runs validation. `PreferenceMigrator` adds the v2 migration step (per L27).

### #078.24 — `WorkflowModeRegistry` skeleton (built-ins + active-mode state)
- [ ] **Goal**: `MainActor` `final class WorkflowModeRegistry: ObservableObject` exposing `@Published activeModeID`, `var allModes: [WorkflowMode]` (built-ins + custom), `func setActive(_ id: String)`, `func mode(for id: String) -> WorkflowMode?`. Built-in `dictation` recipe defined inline: batch shape, `[.transcriber(kind: .asr)]` processors, `[.manualHotkey]` capture controllers, `[.clipboard(restoreEnabled: .setting(...)), .frontmostPaste, .transcriptHistorySQLite]` output sinks.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` (new).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift` — `testRegistryStartsWithDictationBuiltIn`, `testSetActiveAcceptsKnownModeID`, `testSetActiveRejectsUnknownModeID`, `testActiveModeIDPersistsAcrossInstances`.
- **Depends on**: #078.10, #078.11, #078.12.

### #078.25 — `WorkflowModeRegistry.load`/`save` against `workflow-modes.json`
- [ ] **Goal**: Load on init from `AppConfig.baseDirectory()/workflow-modes.json`. On missing file → seed empty `customModes`, `activeModeID = "dictation"`, write document. On parse failure → fall back to built-ins, log; preserve invalid file as `workflow-modes.json.invalid` (round-1 review suggestion #2 — never silently drop user state). On validate failure for one custom mode → skip that mode, keep the rest. Save on every mutation.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` (continued).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryPersistenceTests.swift` — `testLoadCreatesDocumentOnFirstLaunch`, `testLoadFromExistingDocumentRestoresActiveModeID`, `testLoadWithInvalidJsonFallsBackAndPreservesAsDotInvalid`, `testLoadSkipsInvalidCustomModeButKeepsValidOnes`, `testSetActiveWritesUpdatedDocumentToDisk`.
- **Depends on**: #078.24.
- **Migration callout**: this step **creates `workflow-modes.json` on first launch** per design step 7.

### #078.26 — `PreferenceMigrator` v2: legacy global toggles → recipe shape
- [ ] **Goal**: Bump `currentMigrationVersion` to `2`. New `migrateLegacyToggles` reads each of `VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled` from `UserDefaults`. For Dictation recipe: if `VadAutoStopEnabled == true`, append `.vad(...)` to `captureControllers` with parameter values from existing `VadSilenceDurationSeconds`/`VadShowStoppingWarning`/`VadShowAutoStoppedNotification` keys; if `false`, omit `.vad`. If `AutoPasteEnabled == false`, omit `.frontmostPaste` from `outputSinks`. `ClipboardRestoreEnabled` → `.clipboard(restoreEnabled: .override(value))`. Per L27. Migrator runs once; migration writes via `WorkflowModeRegistry.save()`. **Does not delete the legacy keys** — Settings UI still reads/writes them as a bridge (#078.32).
- **Files**: `Sources/PersonalScribeCore/Preferences/PreferenceMigrator.swift`; `Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift` (new — split out so core stays `WorkflowMode`-blind; called from session-tier migrator entry point).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/LegacyToggleMigratorTests.swift` — `testVadOffRemovesVadCaptureController`, `testVadOnAddsVadWithMigratedThreshold`, `testAutoPasteOffOmitsFrontmostPasteSink`, `testClipboardRestoreOnSetsParameterOverride`, `testMigrationIsIdempotentAcrossLaunches`, `testMigrationPreservesLegacyKeysForBridgeReads`.
- **Depends on**: #078.25.

### Phase F close
- [ ] `swift test --filter PersonalScribeSessionTests/WorkflowMode` green.

---

## Phase G — Orchestrator rewrite (`SessionPipelineOrchestrator`)

Goal: orchestrator becomes recipe-driven. No mode-specific branching. Eager descriptor binding at session start (L25).

### #078.27 — `RecipeBuilder` constructs runtime pieces from a `WorkflowMode`
- [ ] **Goal**: New `RecipeBuilder` (or `WorkflowModeRuntimeBuilder`) takes `(mode: WorkflowMode, modelService: ActiveModelService, processorProvider: ModelBoundProcessorProviding, defaults: UserDefaults)`. For each `ProcessorSpec` resolves the descriptor via `modelService.activeDescriptor(for: kind)` (eager — L25), then asks the provider for the typed adapter. For each `Parameter<T>` calls `ParameterResolver.resolve(_:defaults:)` (eager). Returns a `BoundRecipe` value type holding bound adapters + resolved parameters + bound capture/sink instances. Throws `RecipeBuildError.kindHasNoActiveDescriptor` if a referenced kind has no active descriptor.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` (new); `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift` (new).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/RecipeBuilderTests.swift` — `testBuilderResolvesActiveAsrDescriptorEagerly`, `testBuilderThrowsWhenAsrKindHasNoActive`, `testBuilderResolvesParameterOverrideAndSettingFallback`, `testMidBuildSetActiveOnServiceDoesNotAffectAlreadyBoundRecipe` (validates L25).
- **Depends on**: Phase F done.

### #078.28 — `SessionPipelineOrchestrator` consumes `BoundRecipe`
- [ ] **Goal**: Replace orchestrator's hard-coded `prepareTranscriber` + VAD wiring branches with a `BoundRecipe` consumer. Each `CaptureController` instance subscribes to capture lifecycle. Each processor runs in its own task, fed from a shared multicast of the audio stream. Output sinks consume the final `TranscriptionResult` (or `DiarizedTranscript` for diarization recipes). VAD prefs snapshot pattern stays exactly where it is (line 627) — recipe binding inherits the same eager-at-session-start pattern (L25 mirrors precedent). `WorkflowModeRegistry.activeMode()` is read once at session start; mid-session `setActive` is a no-op for the in-flight session.
- **Files**: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` (large rewrite of mode-specific branches).
- **Tests**: `Tests/PersonalScribeSessionTests/Pipeline/Orchestrator/RecipeDrivenOrchestratorTests.swift` — `testOrchestratorBuildsRecipeAtSessionStart`, `testMidSessionActiveModeChangeDoesNotAffectRunningSession`, `testMidSessionActiveModelChangeDoesNotAffectRunningSession`, `testOrchestratorWiresVadCaptureControllerWhenInRecipe`, `testOrchestratorOmitsVadWhenAbsentFromRecipe`, `testOrchestratorRoutesDiarizedRecipeThroughFusionProcessor`.
- **Depends on**: #078.27, #078.23.

### #078.29 — Drop `ServiceBackedActiveModeProvider`; route mode through `WorkflowModeRegistry`
- [ ] **Goal**: Delete `ServiceBackedActiveModeProvider` (lived in `AppComposition.swift`); replace with direct `WorkflowModeRegistry` consumption. `PipelineContextSnapshot.activeMode`, `PostProcessingContext.activeMode` keep their field but feed from registry. `AppStoreActiveModeProviding` protocol either deleted or re-pointed.
- **Files**: `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`; `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineContextSnapshot.swift`; `Sources/PersonalScribeSession/Pipeline/PostProcessing/PostProcessingContext.swift`; `Sources/PersonalScribeSession/AppStore/SessionCoordinator+AppStore.swift`.
- **Tests**: existing tests asserting `activeMode` propagation fixed up; no new tests beyond what #078.28 covers.
- **Depends on**: #078.28.

### Phase G close
- [ ] `swift build --build-tests` green across **all** targets (rename ripple settled).
- [ ] Full `swift test` from canonical repo path.
- [ ] ⚠️ **Runtime verification**: DMG rebuild, manual dictation flow end-to-end (start hotkey, speak, release, transcript pastes). Confirms recipe-driven orchestrator is behavior-neutral for the dictation default.

---

## Phase H — UI catch-up

Goal: AI Models tab and supporting UI surfaces correctly reflect new model kinds. Modes editor UI is **out of scope** per BRIEF.

### #078.30 — `ModelKind.isEnabled` flips
- [ ] **Goal**: Flip `streamingASR` and `diarization` to `true` so AI Models tab surfaces both sections. `vad` and `tts` stay `false` (no adapters land in #078).
- **Files**: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/Models/ModelKindIsEnabledTests.swift` — `testStreamingAsrIsEnabled`, `testDiarizationIsEnabled`, `testVadAndTtsRemainDisabled`. Update existing AI Models tab test fixtures.
- **Depends on**: Phase D done.

### #078.31 — `AIModelsTab` row references `descriptor.engine.kind` (not stored `descriptor.kind`)
- [ ] **Goal**: `AIModelsTab.swift` line 36 uses `descriptor.kind` (today the stored field). Replace with `descriptor.engine.kind`. Same for any other reader. Compiler-driven — but tested.
- **Files**: `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift`; `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` (any internal `descriptor.kind` reads).
- **Tests**: `Tests/PersonalScribeAppKitTests/Settings/AIModelsTabKindRoutingTests.swift` (new) — `testAIModelsTabSectionsByEngineDerivedKind`, `testActiveDescriptorForKindReturnsCorrectEngineMatch`.
- **Depends on**: #078.30, #078.6.

### #078.32 — Settings `GeneralTab` toggle bridge to `WorkflowModeRegistry`
- [ ] **Goal**: Per L27. `GeneralTab` "Auto-stop after silence" toggle reads/writes the active recipe's `CaptureController` list via `WorkflowModeRegistry`. On flip to `true`, append `.vad(...)` (with current setting-resolved parameters) to active recipe's `captureControllers` if absent. On flip to `false`, remove. Same pattern for "Auto-paste" toggle (toggles `.frontmostPaste` sink) and "Restore clipboard" toggle (writes `Parameter.override` on the `.clipboard` sink). Legacy `UserDefaults` keys stay readable as fallback (round-1 review #3); writes hit both for now.
- **Files**: `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift`; `Sources/PersonalScribeAppKit/Settings/VadPreferencePersistence.swift` (rewire writes).
- **Tests**: `Tests/PersonalScribeAppKitTests/Settings/GeneralTabRecipeBridgeTests.swift` — `testFlipVadToggleAddsVadCaptureControllerToActiveRecipe`, `testFlipVadOffRemovesVadCaptureController`, `testFlipAutoPasteOffRemovesFrontmostPasteSink`, `testToggleStateReflectsActiveRecipeAtRender`.
- **Depends on**: Phase F done.

### #078.33 — `AIModelsTab.qwen3` row no longer fails on tap
- [ ] **Goal**: With #078.18 landed, the Qwen3 catalog rows (already `kind: .asr`) now have a working adapter. Verify download → activate → use cycle works for Qwen3 the same way as Parakeet.
- **Files**: no code changes; this step is **manual verification only**.
- **Tests**: add manual entry to `Tests/ManualVerifications/ManualTranscriptionVerification.md` — "Qwen3 ASR (English): download Qwen3-0.6B-int8, activate, record short dictation, confirm transcript appears."
- **Depends on**: #078.18, #078.30, #078.31.
- **⚠️ Runtime verification gate.**

### #078.34 — Manual verification entry for streaming ASR + diarization
- [ ] **Goal**: Add manual checklist entries for streaming ASR (parakeetEOU) and offline diarization. Streaming-typing-as-you-speak end-to-end currently has no UI surface (Modes editor out of scope) — entry documents the AI Models tab download+activate flow and the orchestrator-side smoke test (a script that runs a short audio file through the streaming pipeline and prints partial events).
- **Files**: `Tests/ManualVerifications/ManualTranscriptionsVerification.md` (or new `ManualStreamingVerification.md`); same for `ManualDiarizationVerification.md` (new).
- **Tests**: manual checklist only.
- **Depends on**: #078.30, #078.31.
- **⚠️ Runtime verification gate.**

### Phase H close
- [ ] Full `swift test` green from canonical repo path.
- [ ] DMG rebuild + manual checklist for #078.33 + #078.34 walked.
- [ ] BACKLOG.md: mark #078 done; file follow-up tickets if any.

---

## Dependency table

| Group | Steps | Can parallelize? |
|---|---|---|
| A1 | #078.1, #078.2, #078.6 | Yes (independent core types) |
| A2 | #078.3 | Depends on A1 |
| A3 | #078.4, #078.5 | Yes (parallel; both depend on A1) |
| B1 | #078.7 | Depends on A done |
| B2 | #078.8 | Depends on B1 |
| B3 | #078.9 | Depends on B2 |
| B4 | #078.10, #078.11, #078.12 | Sequential (10 → 11 → 12 share file shape) |
| C1 | #078.13, #078.14, #078.15, #078.16 | Sequential |
| D1 | #078.17 | Depends on C done |
| D2 | #078.18, #078.19, #078.20 | Yes (three new adapters; parallel) |
| E1 | #078.21, #078.22 | Yes |
| E2 | #078.23 | Depends on E1 + D |
| F1 | #078.24, #078.25, #078.26 | Sequential |
| G1 | #078.27, #078.28, #078.29 | Sequential |
| H1 | #078.30, #078.31 | Sequential |
| H2 | #078.32 | Depends on F |
| H3 | #078.33, #078.34 | Manual verification gates; serial |

---

## Migration steps — explicit callouts

1. **`ModelDescriptor.kind` field removal + Codable back-compat** — #078.6. Persisted descriptor blobs continue to decode (legacy `kind` ignored). New encodes omit `kind`. Tests pin both.
2. **`workflow-modes.json` document creation on first launch** — #078.25. Created in `AppConfig.baseDirectory()` with `schemaVersion: 1`, empty `customModes`, `activeModeID: "dictation"`. Idempotent.
3. **Legacy preference migration (`VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled`)** — #078.26. One-shot at first run of v2 migrator; preserves user's prior state into the active recipe. Legacy keys stay readable until Modes editor ships (post-#078).
4. **`ModelKind.isEnabled` flips** — #078.30. `streamingASR` + `diarization` flip `true`. AI Models tab unfilters those rows.
5. **`MuteOutputWhileRecording` and `BackgroundLaunchPreference`** — explicitly **NOT migrated**. Stay as global `UserDefaults` keys. Per L27 + design.

---

## Runtime-verification gates (DMG rebuild + manual test required)

- **Phase D close** — Parakeet still works post-rename (regression check).
- **Phase G close** — Recipe-driven orchestrator behaves identically for Dictation default.
- **#078.33** — Qwen3 ASR works end-to-end.
- **#078.34** — Streaming ASR + offline diarization works end-to-end (smoke-test script + manual checklist).

---

## Open questions for main session

1. **`SettingKey<Value>` placement** — #078.7 puts it in `PersonalScribeCore/Preferences/`. The existing `Preference<Value>` type stays as the live-binding wrapper for SwiftUI — `SettingKey` is the static-typed key that `Parameter<T>.setting(...)` carries. Confirm this layering, or fold `SettingKey` into `Preference`?
2. **`Processor` protocol associated-type vs erased** — #078.21 sketches `Processor` with an `associatedtype Output`. The diarized fusion processor outputs `DiarizedTranscript`; a plain ASR processor outputs `TranscriptionResult`. The orchestrator (#078.28) needs to pump heterogeneous processors through the same plumbing. Erase to a sum type `ProcessorOutput { case transcript(TranscriptionResult), diarized(DiarizedTranscript), streaming(StreamingTranscriptionEvent) }`? Or keep associated-type and switch at the orchestrator boundary on `ProcessorSpec` case? This is the one remaining shape decision the design didn't pin. Default unless told otherwise: **sum type** (simpler dispatch in orchestrator; matches the three `ProcessorSpec` cases 1:1).
3. **Settings-toggle bridge atomicity** (#078.32) — when the user flips the VAD toggle while a session is in progress, mutating the active recipe is allowed (L25 says mid-session changes affect the *next* session). Current `GeneralTab` writes are sync-on-flip. Confirm we don't need to gate writes during an active session — just rely on the snapshot-once pattern at session start. (Default: yes, no gate.)
4. **Phase D adapter rename ripple to existing tests** — `FluidAudioTranscriberTests.swift`, `FluidAudioTranscriberRuntimeVariantTests.swift`, `PrepareIdempotenceTests.swift`, etc. exist for the parakeet-only world. Rename to `FluidAudioParakeetTranscriberAdapter*` and **delete** any tests that pin `FluidAudioRuntimeVariant` cross-family semantics (they're tautological once the enum collapses to parakeet-internal). Confirm the deletion list in the implementation session, or do an inventory step before #078.17.
