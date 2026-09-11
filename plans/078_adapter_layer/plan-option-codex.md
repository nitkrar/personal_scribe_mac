# #078 plan option — Codex

## Lock acknowledgements
- `L1` ✓ `ModelDescriptor` remains the only model identity; `WorkflowMode` stores Kind-oriented recipe specs, not parallel model metadata.
- `L2` ✓ Remove stored `kind` from `ModelDescriptor`; add `TranscriptionEngine.kind`; all selection/UI lookups switch to `descriptor.engine.kind`.
- `L3` ✓ `ModelLifecycle` owns only `prepare()` and `modelDownloadProgress()`.
- `L4` ✓ One FluidAudio Adapter per manager class: Parakeet batch ASR, Qwen batch ASR, Parakeet streaming ASR, speaker diarization.
- `L6` ✓ Active model selection stays `[ModelKind: descriptorID]` in `ActiveModelService`; active Mode moves to `WorkflowModeRegistry`.
- `L7` ✓ Engine→Adapter dispatch happens only inside `ModelBoundProcessorProvider`.
- `L8` ✓ All new cache/runtime types stay FluidAudio-specific.
- `L9` ✓ Keep separate `Transcriber`, `StreamingTranscriber`, and `SpeakerDiarizer` protocols.
- `L10` ✓ `SpeakerDiarizer` is update-oriented and serves batch plus streaming.
- `L11` ✓ `TranscriptionResult` gains optional metadata; UI gates timing/confidence features via `TranscriberCapabilities`.
- `L12` ✓ Fusion is diarize-then-transcribe-per-turn for both Pipeline shapes.
- `L13` ✓ Output protocols compose `ModelLifecycle`; lifecycle is not duplicated.
- `L14` ✓ Modes are recipes of Processors, Capture controllers, and Output sinks; no recipe-specific orchestrator branching.
- `L15` ✓ Shared validity runs at load, save, and session start; invalid persisted Modes fall back to built-in Dictation.
- `L17` ✓ Availability stays global; recipe controls use.
- `L18` ✓ `VadController` inclusion, not a Setting, decides VAD auto-stop.
- `L19` ✓ `Parameter<T>` implements the required cascade centrally.
- `L20` ✓ `WorkflowMode` keeps three role-specific lists; no umbrella `Piece` protocol.

## Architecture sketch (≤300 words)
`Sources/PersonalScribeCore/Transcription/` owns the public seam. `ModelLifecycle` is `func prepare() async throws` plus `func modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>`. `Transcriber: ModelLifecycle` adds `var capabilities: TranscriberCapabilities { get }`, `func transcribe(_ audio: PCMBuffer) async throws -> TranscriptionResult`, and `func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) async throws -> TranscriptionResult`. `StreamingTranscriber: ModelLifecycle` adds `func transcribe(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<StreamingTranscriptionEvent, Error>`. `SpeakerDiarizer: ModelLifecycle` adds `func diarize(stream: AsyncThrowingStream<PCMBuffer, Error>) -> AsyncThrowingStream<SpeakerDiarizationEvent, Error>`; a core extension replays one `PCMBuffer` for batch callers. Batch errors throw; stream errors terminate the returned stream.

`TranscriberCapabilities` is exactly `{ providesTokenTimings, providesConfidence, providesPerformanceMetrics, providesCustomVocabulary }`. Each Adapter declares `static let capabilities` and forwards `var capabilities { Self.capabilities }`. `TranscriptionResult` gains optional `confidence`, `tokenTimings`, `performanceMetrics`, `ctcDetectedTerms`, and `ctcAppliedTerms`.

`WorkflowMode` recipes reference Kind, not descriptor ids: `ProcessorSpec.transcriber(kind: .asr)`, `ProcessorSpec.streamingTranscriber(kind: .streamingASR)`, `ProcessorSpec.diarizedTurns(diarizerKind: .diarization, transcriberKind: .asr)`. Runtime resolution is `ActiveModelService.activeDescriptor(for: kind)` followed by `ModelBoundProcessorProvider`.

`ModelBoundProcessorProvider` exposes `transcriber(for:) throws`, `streamingTranscriber(for:) throws`, and `diarizer(for:) throws`, plus shared `isDownloaded/download/removeDownloadedFiles`. Internally it owns one `[descriptor.id: AdapterRecord]` cache; `switch descriptor.engine` is the only dispatch. Wrong accessor throws `ModelSelectionError.unsupportedKind`.

Fusion is option `(b)`: shared `DiarizedTurnTranscriptionProcessor`. It consumes `SpeakerDiarizationEvent`, buffers source audio, and sends finalized turns to a batch `Transcriber`; batch Modes wait for terminal diarization, streaming Modes emit revisions as turns finalize.

`Parameter<Value>` is `enum { case setting(SettingKey<Value>), override(Value) }`, encoded as `{source,key}` or `{source,value}`. `ParameterResolver` resolves eagerly when building runtime pieces. `WorkflowModeEditorViewModel` exposes each parameter as `Binding<Value>` plus `Binding<Bool>` for `isOverride`; the UI renders “From global” for `.setting` and “Overridden” for `.override`. Each spec declares `validityRules`; `WorkflowModeValidator` runs on load, save, and session start. User Modes persist in `AppConfig.baseDirectory()/workflow-modes.json` as `WorkflowModeDocument(schemaVersion: 1, activeModeID: String?, customModes: [StoredWorkflowMode])`.

## File / type list (≤300 words)
| filename | role | summary |
|---|---|---|
| `Sources/PersonalScribeCore/Transcription/ModelProtocols.swift` | new | `ModelLifecycle`, three output protocols, stream event/result metadata, `TranscriberCapabilities`. |
| `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift` | modified | Drop stored `kind`; add `TranscriptionEngine.kind`; update catalog/codable call sites. |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift` | new | `WorkflowMode`, `PipelineShape`, `ProcessorSpec`, `CaptureControllerSpec`, `OutputSinkSpec`, `Parameter`. |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift` | new | Codable schema for custom Modes plus `schemaVersion` and `activeModeID`. |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift` | new | Central validation over per-spec `validityRules`. |
| `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift` | modified/renamed | Typed provider API plus shared Adapter cache and artifact plumbing. |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` | new | `AsrManager` Adapter with rich metadata capabilities. |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` | new | `Qwen3AsrManager` Adapter with text-only batch ASR. |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` | new | `StreamingEouAsrManager` Adapter producing streaming events. |
| `Sources/PersonalScribeTranscription/Adapters/FluidAudioSpeakerDiarizerAdapter.swift` | new | `Diarizer` Adapter producing provisional/finalized speaker events for batch or streaming. |
| `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTurnTranscriptionProcessor.swift` | new | Shared fusion Processor for speaker-labeled transcript recipes. |
| `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeRegistry.swift` | new | Loads built-in + custom Modes, tracks active Mode, runs migration/validation. |
| `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` | modified | Builds runtime pieces from `WorkflowMode` instead of hard-coded ASR/VAD/output branching. |

## Migration impact (≤200 words)
`WorkflowMode` stops carrying `voiceModelID`/`aiModelID`; active Mode is no longer inferred from the active `.asr` descriptor. `ServiceBackedActiveModeProvider`, `ModesTabViewModel`, `PipelineContextSnapshot`, and `SessionCoordinator` switch to `WorkflowModeRegistry` for Mode state, while `ActiveModelService` stays the per-Kind descriptor owner. `AIModelsTab` still activates descriptors per Kind but no longer implies a Mode change.

Launch migration is one-shot and versioned in `PreferenceMigrator`: create `workflow-modes.json` if missing, seed built-in Dictation as the active Mode, then apply legacy toggles. `VadAutoStopEnabled == false` removes `VadController` from Dictation; `true` includes it and maps `VadSilenceDurationSeconds`, `VadShowStoppingWarning`, and `VadShowAutoStoppedNotification` into `Parameter` entries. `AutoPasteEnabled == true` includes `FrontmostPasteOutputSink`; `false` omits it. `ClipboardRestoreEnabled` becomes a `ClipboardOutputSink` parameter, not recipe inclusion. `MuteOutputWhileRecording` and `BackgroundLaunchPreference` remain global Settings. Invalid or stale persisted custom Modes are skipped during load, the active Mode falls back to Dictation, and the Settings surface shows the validation failure.

## Test seam shape (≤200 words)
Add logic-first tests in `Tests/PersonalScribeCoreTests/WorkflowMode/` for `TranscriptionEngine.kind`, `Parameter` codable round-trip, `ParameterResolver`, `WorkflowModeDocument`, and `WorkflowModeValidator`. Add provider tests proving `transcriber(for:)`, `streamingTranscriber(for:)`, `diarizer(for:)`, `download`, and `removeDownloadedFiles` all hit the same cached `AdapterRecord` and never fork lifecycle state.

Add session tests for `DiarizedTurnTranscriptionProcessor` using `FakeSpeakerDiarizer` event streams and a `FakeTranscriber` that records per-turn audio boundaries; cover batch finalization, streaming incremental finalization, and diarizer/transcriber failure propagation. Add migration tests for `VadAutoStopEnabled=false`, `AutoPasteEnabled=false`, stale `kind` fields in persisted descriptors, and invalid custom Modes. UI work stays at the view-model seam (`ModesTabViewModel`, settings warnings about unavailable features or invalid Modes); any new non-XCTest-able Settings copy gets a manual-verification runbook entry.

## Open questions remaining (≤200 words)
None. Q1-Q8 are concrete in this option. The only sequencing dependency is landing the parallel rename batch first so implementation uses `WorkflowMode`, `PipelineShape`, `Transcriber`, and `AudioCapturer` directly instead of temporary aliases.
