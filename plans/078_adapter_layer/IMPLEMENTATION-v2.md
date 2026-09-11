# Plan: #078 — Adapter layer for non-Parakeet model families (v2)

**Goal**: Land the locked design at `plans/078_adapter_layer/DESIGN.md` v2 — three role-typed output protocols (`Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`), four FluidAudio adapters, recipe-driven `WorkflowMode` composition, eager-bound `Parameter<T>` cascade, recipe-driven orchestrator, and Settings-toggle-as-recipe-builder migration.
**Architecture**: Engine→adapter dispatch lives only in `ModelBoundProcessorProvider` (L24). `ModelLifecycle`-composed protocols (L13). Recipes reference `ModelKind`, late-bound at session start via `ActiveModelService.activeDescriptor(for:)` and frozen for the in-flight session (L25). Fusion processor `DiarizedTurnTranscriptionProcessor` slices audio per finalized turn, drops gaps, ASRs overlap zones end-to-end (L26).
**Tech Stack**: Swift 6 (strict concurrency), SPM, FluidAudio SDK, XCTest. Commit tag prefix `phase-3 step #078.N` per project convention.

## Changes from v1

This revision applies four locked decisions and the round-1 review fixes:

1. **Parallel-build → swap → delete strategy** (Decision 1). Phases A–F now introduce **new** types/protocols/adapters/registry **alongside** existing implementations. Trunk stays buildable at every commit. Phase G is the **cutover** — `AppComposition` rewires to the new types; old code becomes orphaned but still compiles. Phase H is the **delete** — orphaned legacy code (`ModelBoundTranscriberProvider`, `ModelAwareFluidAudioTranscriber`, `FluidAudioRuntimeVariant`, `ServiceBackedActiveModeProvider`, legacy `Transcriber` shape, etc.) gets removed in one atomic pass. Mirrors the project's proven 9-layer central-layers refactor pattern.
2. **Phase H added** for the global delete. New phase, ~6 steps.
3. **Sum-type `Processor` locked** (Decision 2). `Processor.process(audio:priors:) -> ProcessorOutput` enum with `.text`, `.streamingText`, `.turns` cases. Removes the `associatedtype Output` shape from v1.
4. **Critical issues addressed**:
   - C1: F-vs-G ordering — resolved by parallel-build (no in-place mutation between phases).
   - C2: `#078.16` mega-step split into `#078.16a` (production callsites) + `#078.16b` (test fakes), per-file checkboxes.
   - C3: Open question #2 (Processor shape) locked to sum-type.
   - C4: `PCMBufferSlicing` tests extended with stereo, fractional-sample, sample-rate-mismatch coverage.
5. **L-lock partials closed**:
   - L15 partial — added session-start re-validation step in `SessionCoordinator`.
   - L17 partial — voice-ID availability gate documented as out of #078 scope.
6. **Suggestions applied**:
   - Sug 1: per-adapter smoke tests at Phase D close (stub FluidAudio managers via DI).
   - Sug 2: `#078.31`'s test renamed to signal post-deletion bite.
   - Sug 3: `AppStoreActiveModeProviding` locked to delete (per L21 — `WorkflowModeRegistry` replaces it).
   - Sug 5: smoke-test script lives at `scripts/smoke-test-streaming.sh`.
7. **Trunk-only verification cadence** (Decision 3). DMG rebuild + manual user test once at Phase G close. Per-phase: compilation + filtered unit tests. No mid-phase DMG round trips.

Naming convention for parallel build: where a NEW type would name-collide with an existing one, the NEW type lands under a temporary suffixed name (e.g. `Transcriber2`, `RecipeWorkflowMode`) and the rename happens at Phase G cutover. Mirrors central-layers precedent.

## Conventions

- Each step is **2–5 minutes of focused work**, test-first per Ninimma TDD.
- Test + impl land in the **same commit** (TDD discipline).
- Build cadence per sub-step: `swift build --build-tests`. Filtered `swift test --filter <Suite>` at staged-changes checkpoints.
- Full-suite `swift test` only at end-of-phase gates (A, B, C, D, E, F, G, H closure).
- ⚠️ marks steps that need **runtime verification** (DMG build, manual test). Per Decision 3, only Phase G close has this gate.
- Module locations: target names per the rename batch already landed (`Transcriber`, `WorkflowMode`, `PipelineShape`, `PipelineStepID`).

---

## Phase A — Core protocols + types (`PersonalScribeCore`)

Goal: land the new protocol surface and the descriptor reshape **alongside** today's `Transcriber`. Existing parakeet adapter still conforms to today's `Transcriber`. New protocols land as new types.

### #078.1 — `ModelLifecycle` protocol extracted (additive)
- [ ] **Goal**: New `ModelLifecycle` protocol with `prepare()` + `modelDownloadProgress()` per L3/L13. Today's `Transcriber` is **not** modified yet — it keeps its in-line lifecycle methods. New protocol lives alongside; new `Transcriber2` (Phase A.4) will compose it.
- **Files**: `Sources/PersonalScribeCore/Transcription/ModelLifecycle.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/ModelLifecycleTests.swift` — `testModelLifecycleHasOnlyPrepareAndProgress`, `testModelLifecycleIsSendable`.
- **Depends on**: none.

### #078.2 — `TranscriberCapabilities` struct
- [ ] **Goal**: 4-field `Bool` struct (`providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`) per synthesis #1.
- **Files**: `Sources/PersonalScribeCore/Transcription/TranscriberCapabilities.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/TranscriberCapabilitiesTests.swift` — `testAllFieldsDefaultFalse`, `testParakeetCapabilitiesEnableAllFour`, `testQwenCapabilitiesAreTextOnly`.
- **Depends on**: none.

### #078.3 — `TranscriptionResult` gains optional metadata fields (additive)
- [ ] **Goal**: Extend `TranscriptionResult` with optional `confidence: Float?`, `tokenTimings: [TokenTiming]?`, `performanceMetrics: TranscriberPerformanceMetrics?`, `ctcDetectedTerms: [String]?`, `ctcAppliedTerms: [String]?` per L11. Existing call sites unaffected (all-`nil` default). Existing `Transcriber` not modified — `capabilities` accessor is added on the new protocol in #078.4.
- **Files**: `Sources/PersonalScribeCore/TranscriptionResult.swift`; new `Sources/PersonalScribeCore/Transcription/TokenTiming.swift`; new `Sources/PersonalScribeCore/Transcription/TranscriberPerformanceMetrics.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/TranscriptionResultMetadataTests.swift` — `testTranscriptionResultDefaultsAllOptionalMetadataNil`, `testTokenTimingRoundTripsStartEndConfidence`, `testExistingCallSitesCompileWithNoMetadataChange`.
- **Depends on**: #078.2.

### #078.4 — New `Transcriber2` protocol (composes `ModelLifecycle`)
- [ ] **Goal**: New protocol `protocol Transcriber2: ModelLifecycle, Sendable { var capabilities: TranscriberCapabilities { get }; func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult }`. Lives alongside today's `Transcriber`. Suffix `2` is temporary; rename to `Transcriber` at Phase G cutover.
- **Files**: `Sources/PersonalScribeCore/Transcription/Transcriber2.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/Transcriber2ContractTests.swift` — `testTranscriber2ComposesModelLifecycle`, `testTranscriber2RequiresCapabilities`, `testTranscriber2TranscribeReturnsTranscriptionResult`.
- **Depends on**: #078.1, #078.2, #078.3.

### #078.5 — `StreamingTranscriber` protocol
- [ ] **Goal**: `protocol StreamingTranscriber: ModelLifecycle` with `func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error>` + `var capabilities: TranscriberCapabilities`. Event enum cases: `.partial(text:)`, `.endOfUtterance(text:)`, `.finalized(TranscriptionResult)`.
- **Files**: `Sources/PersonalScribeCore/Transcription/StreamingTranscriber.swift` (new); `Sources/PersonalScribeCore/Transcription/StreamingTranscriptionEvent.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/StreamingTranscriberContractTests.swift` — `testStreamingEventCasesAreExhaustive`, `testStreamingTranscriberComposesModelLifecycle`.
- **Depends on**: #078.1, #078.2.

### #078.6 — `SpeakerDiarizer` protocol + event type
- [ ] **Goal**: `protocol SpeakerDiarizer: ModelLifecycle` with `func diarize(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncStream<SpeakerDiarizationEvent>`. Event mirrors FluidAudio's update-oriented shape (L10): `.update(provisional: [SpeakerTurn], finalized: [SpeakerTurn])`, `.terminal([SpeakerTurn])`. `SpeakerTurn { speakerID: String, start: Duration, end: Duration }`. Core extension provides batch convenience `diarize(_ audio: PCMBuffer)` that wraps a one-buffer stream.
- **Files**: `Sources/PersonalScribeCore/Transcription/SpeakerDiarizer.swift` (new); `Sources/PersonalScribeCore/Transcription/SpeakerDiarizationEvent.swift` (new); `Sources/PersonalScribeCore/Transcription/SpeakerTurn.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Transcription/SpeakerDiarizerContractTests.swift` — `testSpeakerTurnPreservesIDAndDurations`, `testDiarizationEventCarriesProvisionalAndFinalizedSeparately`, `testBatchConvenienceWrapsSingleBufferStream`.
- **Depends on**: #078.1.

### #078.7 — `TranscriptionEngine.kind` computed accessor (additive)
- [ ] **Goal**: Add `var kind: ModelKind` on `TranscriptionEngine` mapping `.parakeetTDT → .asr`, `.qwen3ASR → .asr`, `.parakeetEOU → .streamingASR`, `.diarization → .diarization` per L2. **Do NOT remove stored `ModelDescriptor.kind` yet** — that happens at Phase H.6. Today's catalog descriptors keep passing `kind:`. Computed accessor coexists with stored field. Tests pin both return the same value for every catalog descriptor.
- **Files**: `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Kind.swift` (new file — keeps the computed accessor isolated for clean delete-then-rename later).
- **Tests**: `Tests/PersonalScribeCoreTests/Models/TranscriptionEngineKindTests.swift` — `testParakeetTDTMapsToAsr`, `testParakeetEOUMapsToStreamingASR`, `testQwen3ASRMapsToAsr`, `testDiarizationMapsToDiarization` (these are the load-bearing hardcoded mapping tests — no descriptor indirection, no tautology), plus `testEngineKindMappingMatchesCatalogConvention` (renamed from prior `testEngineKindMatchesStoredKindForEveryCatalogDescriptor` — clarified as a convention-consistency check; the actual behavioral oracle for mapping correctness is the four hardcoded tests above + `testSectionsRouteByEngineComputedKindAfterStoredKindRemoval` post-Phase H).
- **Depends on**: nothing (parallel to #078.1–#078.6).

### Phase A close
- [ ] Run `swift build --build-tests` from canonical repo path. All targets compile. Run `swift test --filter PersonalScribeCoreTests`. All green.

---

## Phase B — Mode types (`PersonalScribeCore/WorkflowMode/`)

Goal: add the recipe shape + Codable schema + validator **alongside** today's `WorkflowMode`. New type lands as `RecipeWorkflowMode`; rename to `WorkflowMode` at Phase G cutover. Today's `WorkflowMode { id, name, voiceModelID, aiModelID, systemPrompt }` stays untouched through Phase G.

### #078.8 — `SettingKey<Value>` introduced
- [ ] **Goal**: `SettingKey<Value: Codable & Sendable>` thin wrapper around `String` key + default. Declared in core; conforms `Sendable`. Built atop existing `Preference<Value>` mechanism (resolution via `PreferenceCodec`).
- **Files**: `Sources/PersonalScribeCore/Preferences/SettingKey.swift` (new); `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift` (new — central registry).
- **Tests**: `Tests/PersonalScribeCoreTests/Preferences/SettingKeyTests.swift` — `testSettingKeyResolvesFromUserDefaults`, `testSettingKeyFallsBackToDefaultWhenAbsent`, `testRegistryIncludesVadSilenceThresholdKey`.
- **Depends on**: none.

### #078.9 — `Parameter<Value>` enum + `ParameterResolver`
- [ ] **Goal**: `enum Parameter<Value: Codable & Sendable> { case setting(SettingKey<Value>), override(Value) }`. Codable as `{source: "setting", key: "..."}` or `{source: "override", value: ...}` per L22. `ParameterResolver` is the single resolution site, eager at piece-construction.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/ParameterResolver.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/ParameterCodableTests.swift` — `testSettingCaseEncodesSourceAndKey`, `testOverrideCaseEncodesSourceAndValue`, `testRoundTripPreservesCase`. `Tests/PersonalScribeCoreTests/WorkflowMode/ParameterResolverTests.swift` — `testOverrideWinsOverSetting`, `testSettingFallsBackToHardcodedDefault`, `testResolverReturnsValueAtCallTime`.
- **Depends on**: #078.8.

### #078.10 — `ProcessorSpec`, `CaptureControllerSpec`, `OutputSinkSpec`
- [ ] **Goal**: Three role-specific `enum` spec types per L20. `ProcessorSpec` cases: `.transcriber(kind: ModelKind)`, `.streamingTranscriber(kind: ModelKind)`, `.diarizedTurns(diarizerKind: ModelKind, transcriberKind: ModelKind)`. `CaptureControllerSpec` cases: `.vad(silenceThreshold: Parameter<TimeInterval>, showWarning: Parameter<Bool>, showAutoStoppedNotification: Parameter<Bool>)`, `.manualHotkey`. `OutputSinkSpec` cases: `.clipboard(restoreEnabled: Parameter<Bool>)`, `.frontmostPaste`, `.transcriptHistorySQLite`. All Codable, Equatable, Sendable.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/SpecCodableTests.swift` — `testProcessorSpecDiarizedTurnsRoundTrip`, `testCaptureControllerSpecVadCarriesParameters`, `testOutputSinkSpecClipboardCarriesRestoreParameter`, `testProcessorSpecReferencesKindNotDescriptorID` (asserts no `descriptorID` field — L23).
- **Depends on**: #078.9.

### #078.11 — `RecipeWorkflowMode` type (parallel to legacy)
- [ ] **Goal**: New struct `RecipeWorkflowMode { id, name, pipelineShape: PipelineShape, processors: [ProcessorSpec], captureControllers: [CaptureControllerSpec], outputSinks: [OutputSinkSpec] }` per L1. Lives in a **new file** alongside today's `WorkflowMode.swift`. Today's legacy `WorkflowMode { id, name, voiceModelID, aiModelID, systemPrompt }` is **not modified** — preserves existing `PipelineContextSnapshot.activeMode`, `PostProcessingContext.activeMode`, `StatusItemController.modes`, `ModesTabViewModel`, `ServiceBackedActiveModeProvider`. Build stays green outside core. Rename `RecipeWorkflowMode → WorkflowMode` happens at Phase G cutover (#078.30b) once consumers re-wire.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/RecipeWorkflowMode.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/RecipeWorkflowModeTests.swift` — `testRecipeHoldsThreeRoleLists`, `testDictationDefaultIsBatchPipelineWithTranscriberAndClipboardSink`, `testRecipeCodableRoundTrip`.
- **Depends on**: #078.10.

### #078.12 — `WorkflowModeDocument` Codable schema
- [ ] **Goal**: `struct WorkflowModeDocument: Codable { schemaVersion: Int (=1), activeModeID: String?, customModes: [RecipeWorkflowMode] }` per synthesis #5. References `RecipeWorkflowMode` (the new shape).
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeDocumentTests.swift` — `testDocumentRoundTripPreservesSchemaVersion`, `testDocumentDefaultsActiveModeIDToNil`, `testDocumentDecodesEmptyCustomModesAsEmptyArray`.
- **Depends on**: #078.11.

### #078.13 — `WorkflowModeValidator` (pure-function central)
- [ ] **Goal**: `enum WorkflowModeValidator` with `static func validate(_:) throws`. Rules per L15: at least one processor; processor `.streamingTranscriber` requires `pipelineShape == .streaming`; processor `.diarizedTurns` requires both Kinds enabled in the active model service or fails with `WorkflowModeValidationError.kindUnavailable`; `.diarizedTurns(transcriberKind:)` must be `.asr` or `.streamingASR`; if `.streaming` shape, exactly one streaming processor.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidationError.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeValidatorTests.swift` — `testEmptyProcessorsListIsInvalid`, `testStreamingTranscriberRequiresStreamingShape`, `testDiarizedTurnsRequiresAsrOrStreamingAsrTranscriberKind`, `testValidDictationRecipePassesValidation`, `testValidMeetingRecipePassesValidation`.
- **Depends on**: #078.11.

### Phase B close
- [ ] `swift build --build-tests` green across **all** targets (parallel-build = trunk stays green). `swift test --filter PersonalScribeCoreTests` green.

---

## Phase C — New provider alongside legacy (`PersonalScribeSession`)

Goal: introduce `ModelBoundProcessorProviding` with typed accessors **alongside** today's `ModelBoundTranscriberProviding`. Engine→adapter dispatch lives only in the new provider per L7/L24. The legacy `ModelBoundTranscriberProvider` stays in place — orchestrator and tests still reference it. Cutover at Phase G.

### #078.14 — Define `ModelBoundProcessorProviding` protocol
- [ ] **Goal**: New `protocol ModelBoundProcessorProviding: Sendable { func transcriber(for: ModelDescriptor) throws -> any Transcriber2; func streamingTranscriber(for: ModelDescriptor) throws -> any StreamingTranscriber; func diarizer(for: ModelDescriptor) throws -> any SpeakerDiarizer; func isDownloaded(_:) -> Bool; func download(_:progress:) async throws; func removeDownloadedFiles(_:) throws }`. Wrong-accessor calls throw `ModelSelectionError.unsupportedKind`. Lives alongside existing `ModelBoundTranscriberProviding`. Suffix `2` on `Transcriber2` is temporary; renames at Phase G.
- **Files**: `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProviding.swift` (new). **Do NOT delete** `ModelBoundTranscriberProviding.swift`.
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProvidingTests.swift` — `testProtocolExposesThreeTypedAccessors`, `testProtocolKeepsSharedDownloadAndIsDownloaded`.
- **Depends on**: Phase A done.

### #078.15 — `AdapterRecord` + shared cache infrastructure
- [ ] **Goal**: Internal `AdapterRecord` struct holds the optional `Transcriber2` / `StreamingTranscriber` / `SpeakerDiarizer` adapter for one descriptor. New provider holds `[descriptorID: AdapterRecord]` keyed dict; `isDownloaded`, `download`, `removeDownloadedFiles` route via the record's `ModelLifecycle` so the lifecycle path stays single per L7.
- **Files**: `Sources/PersonalScribeSession/Models/Selection/AdapterRecord.swift` (new — internal).
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/AdapterRecordTests.swift` — `testRecordHoldsThreeOptionalsForOneDescriptor`, `testRecordExposesUniformLifecycleAcrossThreeAdapterTypes`.
- **Depends on**: #078.14.

### #078.16 — Implement `ModelBoundProcessorProvider` (new class, parallel to legacy)
- [ ] **Goal**: New class `ModelBoundProcessorProvider` conforms `ModelBoundProcessorProviding`. Implements three typed accessors. `switch descriptor.engine` is the **only** dispatch (L24). `.parakeetTDT → FluidAudioParakeetTranscriberAdapter`, `.qwen3ASR → FluidAudioQwenTranscriberAdapter`, `.parakeetEOU → FluidAudioStreamingTranscriberAdapter`, `.diarization → FluidAudioOfflineDiarizerAdapter`. Wrong accessor for engine throws `unsupportedKind`. Adapters are stubs in this step (filled in Phase D). Legacy `ModelBoundTranscriberProvider` is **untouched** — both classes coexist.
- **Files**: `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` (new — sibling of `ModelBoundTranscriberProvider.swift`).
- **Tests**: `Tests/PersonalScribeSessionTests/Models/Selection/ModelBoundProcessorProviderTests.swift` — `testTranscriberAccessorThrowsForStreamingEngine`, `testStreamingTranscriberAccessorThrowsForBatchEngine`, `testDiarizerAccessorThrowsForAsrEngine`, `testSameDescriptorReturnsSharedCacheRecord`, `testRemoveDownloadedFilesEvictsAllAdapterTypes`.
- **Depends on**: #078.15.

### Phase C close
- [ ] `swift build --build-tests` green across all targets. `swift test --filter PersonalScribeSessionTests/Models/Selection` green.

---

## Phase D — New adapters (`PersonalScribeTranscription/Adapters/`)

Goal: four FluidAudio adapter classes (L4) land **as new files** alongside the existing `ModelAwareFluidAudioTranscriber`. Today's parakeet path is unaffected — orchestrator still uses the legacy class. Per-adapter unit smoke tests with stub FluidAudio managers via DI (per round-1 review suggestion 1).

### #078.17 — `FluidAudioParakeetTranscriberAdapter` (new file, conforms `Transcriber2`)
- [ ] **Goal**: New class `FluidAudioParakeetTranscriberAdapter` in `Sources/PersonalScribeTranscription/Adapters/`. Conforms `Transcriber2`. Mirrors `ModelAwareFluidAudioTranscriber`'s manager-loading path but exposes the new protocol shape. Declares `static let capabilities = TranscriberCapabilities(providesTokenTimings: true, providesConfidence: true, providesPerformanceMetrics: true, providesCustomVocabulary: true)`. Maps `ASRResult` → extended `TranscriptionResult` with all metadata fields populated. The legacy `ModelAwareFluidAudioTranscriber.swift` is **not deleted** in this phase — Phase H deletes it.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` (new). Do NOT delete legacy files in this step.
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioParakeetTranscriberAdapterTests.swift` — `testCapabilitiesDeclareAllFourTrue`, `testTranscribeReturnsResultWithTokenTimingsPopulated`, `testTranscribeReturnsConfidenceFromAsrResult`, `testAdapterLoadsModelAndExtractsBasicResultUsingStubManager` (stub `AsrManager` injected via DI seam).
- **Depends on**: Phase C done.

### #078.18 — `FluidAudioQwenTranscriberAdapter`
- [ ] **Goal**: New adapter wrapping `Qwen3AsrManager`. Conforms `Transcriber2`. `capabilities = TranscriberCapabilities(.... all false)` per investigation evidence (Qwen3 returns plain `String`). Maps `String → TranscriptionResult(text:, audioDuration:, processingDuration:)`; metadata fields `nil`. `prepare()` delegates to FluidAudio's `Qwen3AsrManager.initialize` after model files present.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioQwenTranscriberAdapterTests.swift` — `testCapabilitiesAreAllFalse`, `testTranscribeReturnsTextOnlyResultWithNilMetadata`, `testPrepareLoadsModelFromDescriptorDirectory`, `testAdapterLoadsModelAndExtractsBasicResultUsingStubManager` (stub `Qwen3AsrManager` via DI seam).
- **Depends on**: #078.17.

### #078.19 — `FluidAudioStreamingTranscriberAdapter`
- [ ] **Goal**: New adapter wrapping `StreamingEouAsrManager`. Conforms `StreamingTranscriber`. Bridges FluidAudio's `partial`/`EOU` callback API to `AsyncThrowingStream<StreamingTranscriptionEvent, Error>`. Per-chunk audio fed via `process(audioBuffer:)`; `partial` emits `.partial(text:)`, EOU emits `.endOfUtterance(text:)`, `finish()` emits `.finalized(...)` and terminates. `capabilities = TranscriberCapabilities(... all false)` (streaming EOU exposes `String` only).
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioStreamingTranscriberAdapterTests.swift` — `testPartialCallbackEmitsPartialEvent`, `testEouCallbackEmitsEndOfUtteranceEvent`, `testFinishEmitsFinalizedEventAndTerminates`, `testStreamErrorTerminatesEventStream`, `testAdapterLoadsModelAndExtractsBasicResultUsingStubManager` (stub `StreamingEouAsrManager` via DI seam).
- **Depends on**: #078.17.

### #078.20 — `FluidAudioOfflineDiarizerAdapter`
- [ ] **Goal**: New adapter wrapping `OfflineDiarizerManager` directly (NOT via FluidAudio's `Diarizer` protocol — review-2 confirmed `OfflineDiarizerManager` does not conform). Conforms our `SpeakerDiarizer`. Degenerate streaming: buffers all audio, calls `process(audio:)` on stream end, emits one `.terminal([SpeakerTurn])`. Maps FluidAudio `TimedSpeakerSegment` → our `SpeakerTurn`.
- **Files**: `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift` (new).
- **Tests**: `Tests/PersonalScribeTranscriptionTests/Adapters/FluidAudioOfflineDiarizerAdapterTests.swift` — `testDegenerateStreamingEmitsSingleTerminalEvent`, `testTerminalEventCarriesAllTurnsFromOfflineManager`, `testEmptyAudioStreamProducesEmptyTerminalEvent`, `testAdapterLoadsModelAndExtractsBasicResultUsingStubManager` (stub `OfflineDiarizerManager` via DI seam).
- **Depends on**: #078.17.

### Phase D close
- [ ] `swift build --build-tests` green. `swift test --filter PersonalScribeTranscriptionTests/Adapters` green.
- [ ] No DMG runtime gate per Decision 3 — adapter smoke tests via stub managers cover the FluidAudio API misunderstanding risk that was deferred in v1. End-to-end runtime verification at Phase G close.

---

## Phase E — Fusion processor (`PersonalScribeSession/Pipeline/Processors/`)

Goal: shared `DiarizedTurnTranscriptionProcessor` per L26. Composable piece. **Sum-type `Processor` locked** per Decision 2.

### #078.21 — `Processor` role-protocol with sum-type output
- [ ] **Goal**: Tiny role protocol `protocol Processor: ModelLifecycle, Sendable { func process(audio: PCMBuffer, priors: [ProcessorOutput]) async throws -> ProcessorOutput }`. Output is the sum type:
```
enum ProcessorOutput: Sendable {
    case text(TranscriptionResult)
    case streamingText(AsyncThrowingStream<StreamingTranscriptionEvent, Error>)
    case turns(AsyncStream<SpeakerDiarizationEvent>)
}
```
The orchestrator (#078.28) dispatches via `switch` on `ProcessorOutput`. Locks open question #2 from v1.
- **Files**: `Sources/PersonalScribeCore/WorkflowMode/Processor.swift` (new); `Sources/PersonalScribeCore/WorkflowMode/ProcessorOutput.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/WorkflowMode/ProcessorContractTests.swift` — `testProcessorOutputCasesAreExhaustive`, `testProcessorComposesModelLifecycle`, `testProcessOutputCarriesAsyncStreamForTurnsCase`.
- **Depends on**: Phase A done.

### #078.22 — Audio-slice helper
- [ ] **Goal**: Pure-function helper `func slice(_ pcmBuffer: PCMBuffer, from: Duration, to: Duration) -> PCMBuffer`. Sample-accurate based on the buffer's sample rate. Used by the fusion processor to send per-turn audio to the batch transcriber.
- **Files**: `Sources/PersonalScribeCore/Audio/PCMBufferSlicing.swift` (new).
- **Tests**: `Tests/PersonalScribeCoreTests/Audio/PCMBufferSlicingTests.swift`:
  - `testSliceReturnsSampleAccurateRange`
  - `testSliceClampsToBufferBounds`
  - `testSliceOfZeroDurationReturnsEmptyBuffer`
  - `testSliceWithStereoBufferPreservesChannels` (or, if implementation pins mono-only, rename to `testSliceWithStereoBufferThrowsMonoOnlyInvariant` and document the invariant)
  - `testSliceWithFractionalSampleStartUsesNearestSampleBoundary` (round-toward-start for `from`, round-toward-end for `to` — pin direction in test)
  - `testSliceWithSampleRateMismatchThrowsOrConverts` (pin behavior — current expectation: throw `PCMBufferSliceError.sampleRateMismatch`; do not silently convert)
- **Depends on**: none.

### #078.23 — `DiarizedTurnTranscriptionProcessor` — finalize-only path
- [ ] **Goal**: Conforms `Processor`. On `process(audio:priors:)`: fans audio into both the `SpeakerDiarizer` and an internal accumulator. On `.terminal([turns])` (or `.update(finalized: …)`), for each finalized turn slices accumulated audio per timestamps, sends to bound `Transcriber2` via `transcribe(_:)`. Emits `(speakerID, TranscriptionResult)` pairs as a `DiarizedTranscript` payload, surfaced through `ProcessorOutput.turns(...)` (the sum-type case carrying the speaker-event stream — for diarized-turn output the orchestrator collects from this stream and merges with per-turn ASR via the recipe builder). Implements L26: gaps drop, overlap zones ASR end-to-end, provisional ignored.
- **Files**: `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTurnTranscriptionProcessor.swift` (new); `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTranscript.swift` (new — output payload struct).
- **Tests**: `Tests/PersonalScribeSessionTests/Pipeline/Processors/DiarizedTurnTranscriptionProcessorTests.swift`:
  - `testFinalizedTurnsTriggerOnePerSpeakerTranscribeCall`
  - `testGapBetweenTurnsIsNotTranscribed`
  - `testOverlapZoneIsTranscribedTwiceEndToEnd` (turn A 0–5s, turn B 3–8s → 2 calls; slice for A is 0–5s, slice for B is 3–8s; both include 3–5s)
  - `testProvisionalTurnsAreNotTranscribed`
  - `testDiarizerErrorTerminatesOutputStream`
  - `testTranscriberErrorOnOneTurnDoesNotPreventOtherTurns` (per-turn isolation per L26)
- **Depends on**: #078.21, #078.22, #078.20, #078.17.

### Phase E close
- [ ] `swift build --build-tests` green. `swift test --filter PersonalScribeSessionTests/Pipeline/Processors` green.

---

## Phase F — Registry + migration (parallel to legacy active-mode)

Goal: `WorkflowModeRegistry` (L21) loads/saves `WorkflowModeDocument`, owns active-mode state, runs validation. `PreferenceMigrator` adds the v2 migration step (L27). Today's `ServiceBackedActiveModeProvider` is **untouched**; orchestrator still consumes it. Phase G cutover swaps the consumer.

**Critical-issue C1 resolution**: Phase F's migration creates `workflow-modes.json`; the new `WorkflowModeRegistry` reads it; the **old** orchestrator never sees it (it stays on `ServiceBackedActiveModeProvider`). At Phase G cutover (#078.30a/b + #078.31a), `AppComposition` swaps the orchestrator wiring — the new orchestrator now consumes the migrated state. There is no interim window where new state exists with no consumer.

### #078.24 — `WorkflowModeRegistry` skeleton (built-ins + active-mode state)
- [ ] **Goal**: `MainActor final class WorkflowModeRegistry: ObservableObject` exposing `@Published activeModeID`, `var allModes: [RecipeWorkflowMode]` (built-ins + custom), `func setActive(_ id: String)`, `func mode(for id: String) -> RecipeWorkflowMode?`. Built-in `dictation` recipe defined inline: batch shape, `[.transcriber(kind: .asr)]`, `[.manualHotkey]`, `[.clipboard(restoreEnabled: .setting(...)), .frontmostPaste, .transcriptHistorySQLite]`. Lives alongside `ServiceBackedActiveModeProvider` — both classes compile and run.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` (new).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift` — `testRegistryStartsWithDictationBuiltIn`, `testSetActiveAcceptsKnownModeID`, `testSetActiveRejectsUnknownModeID`, `testActiveModeIDPersistsAcrossInstances`.
- **Depends on**: #078.11, #078.12, #078.13.

### #078.25 — `WorkflowModeRegistry.load`/`save` against `workflow-modes.json`
- [ ] **Goal**: Load on init from `AppConfig.baseDirectory()/workflow-modes.json`. On missing file → seed empty `customModes`, `activeModeID = "dictation"`, write document. On parse failure → fall back to built-ins, log; preserve invalid file as `workflow-modes.json.invalid`. On validate failure for one custom mode → skip that mode, keep the rest. Save on every mutation. Note: nothing reads this file outside the registry until Phase G cutover — no orphan-state risk.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` (continued).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryPersistenceTests.swift` — `testLoadCreatesDocumentOnFirstLaunch`, `testLoadFromExistingDocumentRestoresActiveModeID`, `testLoadWithInvalidJsonFallsBackAndPreservesAsDotInvalid`, `testLoadSkipsInvalidCustomModeButKeepsValidOnes`, `testSetActiveWritesUpdatedDocumentToDisk`.
- **Depends on**: #078.24.

### #078.26 — `PreferenceMigrator` v2: legacy global toggles → recipe shape
- [ ] **Goal**: Bump `currentMigrationVersion` to `2`. New `migrateLegacyToggles` reads each of `VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled` from `UserDefaults`. For Dictation recipe: if `VadAutoStopEnabled == true`, append `.vad(...)` to `captureControllers` with parameter values from `VadSilenceDurationSeconds`/`VadShowStoppingWarning`/`VadShowAutoStoppedNotification`; if `false`, omit. If `AutoPasteEnabled == false`, omit `.frontmostPaste`. `ClipboardRestoreEnabled` → `.clipboard(restoreEnabled: .override(value))`. Per L27. Migrator runs once. Migration writes via `WorkflowModeRegistry.save()`. **Does not delete legacy keys** — Settings UI still reads them as a bridge (#078.32).
- **Files**: `Sources/PersonalScribeCore/Preferences/PreferenceMigrator.swift`; `Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift` (new).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/LegacyToggleMigratorTests.swift` — `testVadOffRemovesVadCaptureController`, `testVadOnAddsVadWithMigratedThreshold`, `testAutoPasteOffOmitsFrontmostPasteSink`, `testClipboardRestoreOnSetsParameterOverride`, `testMigrationIsIdempotentAcrossLaunches`, `testMigrationPreservesLegacyKeysForBridgeReads`.
- **Depends on**: #078.25.

### Phase F close
- [ ] `swift build --build-tests` green across all targets. `swift test --filter PersonalScribeSessionTests/WorkflowMode` green.

---

## Phase G — CUTOVER (orchestrator rewrite + rewire)

Goal: orchestrator becomes recipe-driven. `AppComposition` rewires every consumer to the new types. **No legacy code is deleted in Phase G** — old becomes orphaned but still compiles. Decision 3 sets the runtime gate at this phase close.

### #078.27 — `RecipeBuilder` constructs runtime pieces from a `RecipeWorkflowMode`
- [ ] **Goal**: New `RecipeBuilder` takes `(mode: RecipeWorkflowMode, modelService: ActiveModelService, processorProvider: ModelBoundProcessorProviding, defaults: UserDefaults)`. For each `ProcessorSpec` resolves the descriptor via `modelService.activeDescriptor(for: kind)` (eager — L25), then asks the provider for the typed adapter. For each `Parameter<T>` calls `ParameterResolver.resolve(_:defaults:)` (eager). Returns a `BoundRecipe` value type holding bound adapters + resolved parameters + bound capture/sink instances. Throws `RecipeBuildError.kindHasNoActiveDescriptor` if a referenced kind has no active descriptor.
- **Files**: `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` (new); `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift` (new).
- **Tests**: `Tests/PersonalScribeSessionTests/WorkflowMode/RecipeBuilderTests.swift` — `testBuilderResolvesActiveAsrDescriptorEagerly`, `testBuilderThrowsWhenAsrKindHasNoActive`, `testBuilderResolvesParameterOverrideAndSettingFallback`, `testMidBuildSetActiveOnServiceDoesNotAffectAlreadyBoundRecipe` (L25).
- **Depends on**: Phase F done.

### #078.28 — `SessionCoordinator` re-validates active mode at session start (L15 partial)
- [ ] **Goal**: Before delegating to `RecipeBuilder`, `SessionCoordinator` calls `WorkflowModeValidator.validate(_:)` on the active recipe. If validation fails, surface a descriptive error to the response card and abort the session (do not start capture). Closes L15 partial: validation now fires at save (registry), build (recipe builder), AND session start (coordinator).
- **Files**: `Sources/PersonalScribeSession/SessionCoordinator.swift` (add validation call before recipe build).
- **Tests**: `Tests/PersonalScribeSessionTests/SessionCoordinatorValidationTests.swift` — `testSessionStartRevalidatesActiveModeAndFailsWithDescriptiveErrorIfInvalid`, `testSessionStartProceedsWhenActiveModeValidates`.
- **Depends on**: #078.27.

### #078.29 — Recipe-driven `SessionPipelineOrchestrator`
- [ ] **Goal**: Replace orchestrator's hard-coded `prepareTranscriber` + VAD wiring branches with a `BoundRecipe` consumer. Each `CaptureController` instance subscribes to capture lifecycle. Each processor runs in its own task; orchestrator dispatches per `ProcessorOutput` case (`.text`, `.streamingText`, `.turns`). Output sinks consume the final result. VAD prefs snapshot pattern stays at line 627 — recipe binding inherits the eager-at-session-start pattern (L25). `WorkflowModeRegistry.activeMode()` is read once at session start; mid-session `setActive` is a no-op for the in-flight session.
- **Files**: `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` (large rewrite of mode-specific branches).
- **Tests**: `Tests/PersonalScribeSessionTests/Pipeline/Orchestrator/RecipeDrivenOrchestratorTests.swift` — `testOrchestratorBuildsRecipeAtSessionStart`, `testMidSessionActiveModeChangeDoesNotAffectRunningSession`, `testMidSessionActiveModelChangeDoesNotAffectRunningSession`, `testOrchestratorWiresVadCaptureControllerWhenInRecipe`, `testOrchestratorOmitsVadWhenAbsentFromRecipe`, `testOrchestratorRoutesDiarizedRecipeThroughFusionProcessor`, `testOrchestratorDispatchesProcessorOutputBySumTypeCase`.
- **Depends on**: #078.28, #078.23.

### #078.30a — Cutover rename: `Transcriber` family (per-file checkbox)
- [ ] **Goal** (split from v1's #078.30 to avoid mega-step per round-2 review issue 1): rename legacy `Transcriber` → `LegacyTranscriber`, then rename new `Transcriber2` → `Transcriber`. **Pure rename; zero behavioral change.** Per-file:
  - [ ] `Sources/PersonalScribeCore/Protocols.swift` — legacy `Transcriber` → `LegacyTranscriber`.
  - [ ] `Sources/PersonalScribeCore/Transcription/Transcriber2.swift` → renamed file `Transcriber.swift` (and type inside).
  - [ ] `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` — `: Transcriber2` → `: Transcriber`.
  - [ ] `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` — same.
  - [ ] `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProviding.swift` — `any Transcriber2` → `any Transcriber`.
  - [ ] `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` — return type rename.
  - [ ] All test files referencing `Transcriber2` (grep `Transcriber2` under `Tests/` to inventory; expect 4–8 fake/spec files in `Tests/PersonalScribeSessionTests/` and `Tests/PersonalScribeTranscriptionTests/`).
- **Tests**: existing tests rename their imports + type references. `swift build --build-tests` green is the gate.
- **Depends on**: #078.29.

### #078.30b — Cutover rename: `WorkflowMode` family (per-file checkbox)
- [ ] **Goal** (split from v1's #078.30 to avoid mega-step per round-2 review issue 1): rename legacy `WorkflowMode` → `LegacyWorkflowMode`, then rename new `RecipeWorkflowMode` → `WorkflowMode`. **Pure rename; zero behavioral change.** Per-file:
  - [ ] `Sources/PersonalScribeCore/WorkflowMode.swift` — legacy `WorkflowMode` → renamed file `LegacyWorkflowMode.swift`.
  - [ ] `Sources/PersonalScribeCore/WorkflowMode/RecipeWorkflowMode.swift` → renamed file `WorkflowMode.swift` (and type inside).
  - [ ] `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift` — `RecipeWorkflowMode` → `WorkflowMode` references.
  - [ ] `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift` — same.
  - [ ] `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` — same.
  - [ ] `Sources/PersonalScribeSession/Pipeline/RecipeBuilder.swift` — same.
  - [ ] All test files referencing `RecipeWorkflowMode` (grep under `Tests/` to inventory; expect 3–6 files).
- **Tests**: existing tests rename their imports + type references. `swift build --build-tests` green is the gate.
- **Depends on**: #078.30a (serialize the renames; safer to land Transcriber rename first, then WorkflowMode rename).

### #078.31a — Production callsite rewire (per-file checkbox)
- [ ] **Goal** (split from v1's #078.16 mega-step per critical-issue C2): rewire each production callsite to use the new `ModelBoundProcessorProviding` + `WorkflowModeRegistry` instead of `ModelBoundTranscriberProviding` + `ServiceBackedActiveModeProvider`. Per-file:
  - [ ] `Sources/PersonalScribeAppKit/Composition/AppComposition.swift` — swap provider construction; swap active-mode source.
  - [ ] `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — call-site only (orchestrator body landed in #078.29).
  - [ ] `Sources/PersonalScribeSession/SessionCoordinator.swift` — swap provider injection.
  - [ ] `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineContextSnapshot.swift` — `activeMode` field feeds from registry.
  - [ ] `Sources/PersonalScribeSession/Pipeline/PostProcessing/PostProcessingContext.swift` — same.
  - [ ] `Sources/PersonalScribeSession/AppStore/SessionCoordinator+AppStore.swift` — registry-backed.
- **Tests**: existing tests must keep passing through this rewire. Add one explicit cutover-correctness test at this step (per round-2 review issue 3): `Tests/PersonalScribeAppKitTests/Composition/AppCompositionRecipeBackedTests.swift` — `testAppCompositionInjectsWorkflowModeRegistryNotLegacyProvider` (asserts `AppComposition.makeSessionPipelineOrchestrator()` resolves the orchestrator's mode source through `WorkflowModeRegistry`, not `ServiceBackedActiveModeProvider`).
- **Depends on**: #078.30b.

### #078.31b — Test-fake rewire (per-file checkbox)
- [ ] **Goal** (split from v1's #078.16 mega-step per critical-issue C2): update every test fake under `Tests/PersonalScribeSessionTests/` referencing the legacy provider. Per-file:
  - [ ] `Tests/PersonalScribeSessionTests/Models/Selection/Fakes/FakeModelBoundTranscriberProvider.swift` (or equivalent — inventory at start of step; rename to `FakeModelBoundProcessorProvider`).
  - [ ] Any orchestrator test file that constructs the provider fake directly (grep `ModelBoundTranscriberProviding` under `Tests/`).
  - [ ] Any `ServiceBackedActiveModeProvider`-using test fake (grep similarly).
- **Tests**: existing test names preserved; only provider construction lines change. `swift test` green.
- **Depends on**: #078.31a.

### #078.32 — `ModelKind.isEnabled` flips
- [ ] **Goal**: Flip `streamingASR` and `diarization` to `true`. AI Models tab surfaces both sections. `vad` and `tts` stay `false`.
- **Files**: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/Models/ModelKindIsEnabledTests.swift` — `testStreamingAsrIsEnabled`, `testDiarizationIsEnabled`, `testVadAndTtsRemainDisabled`. Update existing AI Models tab test fixtures.
- **Depends on**: #078.31b.

### #078.33 — Settings `GeneralTab` toggle bridge to `WorkflowModeRegistry`
- [ ] **Goal**: Per L27. `GeneralTab` toggles read/write the active recipe via `WorkflowModeRegistry`. "Auto-stop after silence" — flip to `true` appends `.vad(...)` if absent; flip to `false` removes. "Auto-paste" — toggles `.frontmostPaste`. "Restore clipboard" — writes `Parameter.override` on `.clipboard`. Legacy `UserDefaults` keys stay readable as fallback; writes hit both for now (deleted in Phase H).
- **Files**: `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift`; `Sources/PersonalScribeAppKit/Settings/VadPreferencePersistence.swift` (rewire writes).
- **Tests**: `Tests/PersonalScribeAppKitTests/Settings/GeneralTabRecipeBridgeTests.swift` — `testFlipVadToggleAddsVadCaptureControllerToActiveRecipe`, `testFlipVadOffRemovesVadCaptureController`, `testFlipAutoPasteOffRemovesFrontmostPasteSink`, `testToggleStateReflectsActiveRecipeAtRender`.
- **Depends on**: #078.31a.

### Phase G close
- [ ] `swift build --build-tests` green across all targets.
- [ ] Full `swift test` from canonical repo path. All green.
- [ ] ⚠️ **Runtime verification (the only DMG gate per Decision 3)**: DMG rebuild, manual dictation flow end-to-end (start hotkey, speak, release, transcript pastes). Confirms recipe-driven orchestrator is behavior-neutral for the dictation default.

---

## Phase H — DELETE (orphaned legacy code)

Goal: remove the now-orphaned legacy types in one atomic pass. Mirrors central-layers Stage 3 global delete.

### #078.34 — Delete legacy `LegacyTranscriber` protocol + `ModelBoundTranscriberProvider` + provider protocol
- [ ] **Goal**: Delete `LegacyTranscriber`, `ModelBoundTranscriberProviding`, `ModelBoundTranscriberProvider`. Verify zero references via `swift build`.
- **Files**: delete `Sources/PersonalScribeCore/Protocols.swift` (LegacyTranscriber definition — keep only what remains relevant); delete `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProviding.swift`; delete `Sources/PersonalScribeSession/Models/Selection/ModelBoundTranscriberProvider.swift`.
- **Tests**: no new tests; build is the gate.
- **Depends on**: Phase G done.

### #078.35 — Delete legacy parakeet adapter + runtime variant
- [ ] **Goal**: Delete `ModelAwareFluidAudioTranscriber.swift`, `FluidAudioRuntimeVariant.swift`, `ModelAwareFluidAudioInferenceClient.swift`. Inline `FluidAudioRuntimeVariant` cases as parakeet-internal detail of `FluidAudioParakeetTranscriberAdapter` (was a pre-step in v1's #078.17; landed here under parallel-build). If `FluidAudioInferenceClient.swift` also imports the runtime-variant enum, edit it to drop the parameter or delete it as well — verify in this step (review-1 spot-check).
- **Files**: delete the listed legacy files; touch `FluidAudioParakeetTranscriberAdapter.swift` to inline the variant detail.
- **Tests**: existing parakeet adapter tests remain green.
- **Depends on**: #078.34.

### #078.36 — Delete `LegacyWorkflowMode` + `ServiceBackedActiveModeProvider` + `AppStoreActiveModeProviding`
- [ ] **Goal**: Delete `LegacyWorkflowMode.swift` (the renamed legacy `WorkflowMode` from #078.30b). Delete `ServiceBackedActiveModeProvider`. Delete `AppStoreActiveModeProviding` protocol entirely (per round-1 review suggestion 3 + L21: `WorkflowModeRegistry` replaces it; no re-pointing).
- **Files**: delete `Sources/PersonalScribeCore/LegacyWorkflowMode.swift`; delete `ServiceBackedActiveModeProvider` from `Sources/PersonalScribeAppKit/Composition/AppComposition.swift`; delete `AppStoreActiveModeProviding.swift` (locate in current tree at start of step).
- **Tests**: no new tests; build + remaining test suite green.
- **Depends on**: #078.34.

### #078.37 — Remove stored `ModelDescriptor.kind` field + Codable back-compat
- [ ] **Goal**: Remove stored `kind` from `ModelDescriptor`. Catalog descriptors stop passing `kind:`. **Codable migration**: `ModelDescriptor+Codable.swift` ignores legacy `kind` field on decode (back-compat for any persisted descriptor blobs); never encodes `kind`. Computed accessor from #078.7 is the single source of truth post-delete.
- **Files**: `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`; `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor+Codable.swift`; `Sources/PersonalScribeCore/Models/Selection/BuiltInModelCatalog.swift`; `Sources/PersonalScribeCore/Models/Selection/TranscriptionEngine+Codable.swift`.
- **Tests**: `Tests/PersonalScribeCoreTests/Models/ModelDescriptorCodableLegacyKindTests.swift` — `testDecodeWithLegacyKindFieldDropsItSilently`, `testEncodeOmitsKindField`. Existing tests asserting `descriptor.kind` are rewritten to use `descriptor.engine.kind`.
- **Depends on**: #078.36.

### #078.38 — `AIModelsTab` reads `descriptor.engine.kind`
- [ ] **Goal**: `AIModelsTab.swift:36` and any other reader of `descriptor.kind` (the now-deleted stored field) switches to `descriptor.engine.kind`. Compiler-driven for the call-site change; behaviorally tested post-deletion.
- **Files**: `Sources/PersonalScribeAppKit/Settings/AIModelsTab.swift`; `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` (any internal reads).
- **Tests**: `Tests/PersonalScribeAppKitTests/Settings/AIModelsTabKindRoutingTests.swift` (new) — `testSectionsRouteByEngineComputedKindAfterStoredKindRemoval` (renamed per round-1 suggestion 2 — only has bite post-deletion), `testActiveDescriptorForKindReturnsCorrectEngineMatch`.
- **Depends on**: #078.37.

### #078.39 — Manual verification entries
- [ ] **Goal**: Add manual-verification checklist entries for streaming ASR (parakeetEOU), offline diarization, and Qwen3 ASR. Smoke-test script lives at `scripts/smoke-test-streaming.sh` (per round-1 suggestion 5) — runs a short audio file through the streaming pipeline and prints partial events.
- **Files**: `Tests/ManualVerifications/ManualTranscriptionVerification.md` — add Qwen3 entry; new `Tests/ManualVerifications/ManualStreamingVerification.md`; new `Tests/ManualVerifications/ManualDiarizationVerification.md`; new `scripts/smoke-test-streaming.sh`.
- **Tests**: manual checklists only.
- **Depends on**: #078.38.

### Phase H close
- [ ] Full `swift test` green from canonical repo path.
- [ ] DMG rebuild + manual checklist for #078.39 walked.
- [ ] BACKLOG.md: mark #078 done; file follow-up tickets if any.

---

## Dependency table

| Group | Steps | Can parallelize? |
|---|---|---|
| A1 | #078.1, #078.2, #078.7 | Yes (independent core types) |
| A2 | #078.3 | Depends on A1 |
| A3 | #078.4, #078.5, #078.6 | Yes (parallel; all depend on A1/A2) |
| B1 | #078.8 | Depends on A done |
| B2 | #078.9 | Depends on B1 |
| B3 | #078.10 | Depends on B2 |
| B4 | #078.11, #078.12, #078.13 | Sequential |
| C1 | #078.14, #078.15, #078.16 | Sequential |
| D1 | #078.17 | Depends on C done |
| D2 | #078.18, #078.19, #078.20 | Yes (three new adapters; parallel) |
| E1 | #078.21, #078.22 | Yes |
| E2 | #078.23 | Depends on E1 + D |
| F1 | #078.24, #078.25, #078.26 | Sequential |
| G1 | #078.27, #078.28, #078.29 | Sequential |
| G2a | #078.30a | Depends on #078.29 |
| G2b | #078.30b | Depends on #078.30a |
| G3 | #078.31a | Depends on #078.30b |
| G4 | #078.31b | Depends on #078.31a |
| G5 | #078.32, #078.33 | Yes (parallel; both post-rewire) |
| H1 | #078.34, #078.35, #078.36 | Sequential |
| H2 | #078.37 | Depends on H1 |
| H3 | #078.38, #078.39 | Sequential |

---

## Migration steps — explicit callouts

1. **`workflow-modes.json` document creation on first launch** — #078.25. Created in `AppConfig.baseDirectory()` with `schemaVersion: 1`, empty `customModes`, `activeModeID: "dictation"`. Idempotent. **No orphan-state risk** between F-close and G-close because the file is only read by the new registry; the old orchestrator never touches it (C1 fix).
2. **Legacy preference migration (`VadAutoStopEnabled`, `AutoPasteEnabled`, `ClipboardRestoreEnabled`)** — #078.26. One-shot at first run of v2 migrator; preserves user's prior state into the active recipe. Legacy keys stay readable until #078.33 stabilises and Phase H clears them (Settings UI is the bridge).
3. **`ModelKind.isEnabled` flips** — #078.32. `streamingASR` + `diarization` flip `true`. AI Models tab unfilters those rows.
4. **Stored `ModelDescriptor.kind` field removal + Codable back-compat** — #078.37. Persisted descriptor blobs continue to decode (legacy `kind` ignored). New encodes omit `kind`. Tests pin both.
5. **`MuteOutputWhileRecording` and `BackgroundLaunchPreference`** — explicitly **NOT migrated**. Stay as global `UserDefaults` keys per L27.

---

## Runtime-verification gates (DMG rebuild + manual test required)

- **Phase G close** — Recipe-driven orchestrator behaves identically for Dictation default. **The only DMG gate per Decision 3.**
- **#078.39** — Manual checklist for Qwen3 ASR + streaming ASR + offline diarization (post-Phase H delete; rolls into Phase H close).

Per Decision 3, no per-phase DMG rebuild between A and G. Compilation + filtered unit tests gate each phase. Adapter-level FluidAudio API misunderstanding risk is covered by stub-manager smoke tests at Phase D close (round-1 suggestion 1).

---

## Out of scope (explicit)

- **Voice-ID availability gate (L17 hybrid γ)** — closes L17 partial. No voice-ID processor lands in #078; the hybrid γ availability/use split (`global setting controls availability` + `recipe controls use`) is well-defined in L17 but has no concrete piece to apply to in this ticket. Out of #078 scope. When voice-ID lands, the global "voice-ID enrolled & ready" preference reads from `UserDefaults`, and `VoiceIDLabeler` becomes a recipe-piece subject to per-mode opt-in.
- **LSEEND streaming diarization adapter** — separate ticket. Test offline diarization quality first.
- **Backend-agnostic abstraction** — deferred until a second SDK appears (per L8).
- **`Parameter<T>` schema versioning / migration** — deferred per CHECKLIST Hole 3.
- **Modes UI editor for custom recipes** — separate UX ticket.
- **Realtime typing of diarized output** — out of scope per L26.

---

## Locked design decisions (this revision)

- **D1** Parallel-build → swap → delete strategy. Phases A–F additive. Phase G cutover. Phase H delete. Trunk green every commit.
- **D2** `Processor` is sum-type with `ProcessorOutput { case text, case streamingText, case turns }`.
- **D3** Trunk-only verification, end-of-impl user test at Phase G close. No per-phase DMG.

---

## Open questions

None remaining. All four critical issues from review-1 resolved by D1/C2/D2/C4. All five suggestions applied. L15 partial closed by #078.28; L17 partial closed via Out-of-scope section.
