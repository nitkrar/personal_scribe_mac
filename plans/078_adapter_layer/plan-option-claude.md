# #078 plan option — claude

## Lock acknowledgements

- **L1** ✓ One `ModelDescriptor`. Adapter cache keyed by `descriptor.id`.
- **L2** ✓ `kind` becomes computed on `TranscriptionEngine`. Catalog drops `kind:`. Codable migration adds back-compat decode that ignores legacy `kind` field.
- **L3** ✓ `ModelLifecycle` is its own protocol; `Transcriber`/`StreamingTranscriber`/`SpeakerDiarizer` compose it.
- **L4** ✓ One adapter per FluidAudio manager. `FluidAudioRuntimeVariant` collapses into `ParakeetTDTAdapter` private detail.
- **L6** ✓ `ActiveModelService` keeps `[ModelKind: descriptorID]`.
- **L7** ✓ `EngineProvider` (renamed from provider) dispatches engine→adapter; typed accessors.
- **L8** ✓ Adapters import FluidAudio directly. No backend abstraction layer.
- **L9** ✓ Three protocols, no umbrella.
- **L10** ✓ One `SpeakerDiarizer` carrying batch + streaming via update-oriented events.
- **L11** ✓ `TranscriptionResult` gains optional metadata; `TranscriberCapabilities` declared per adapter.
- **L12** ✓ Diarize-then-transcribe-per-turn, same rule batch + streaming.
- **L13** ✓ See L3.
- **L14** ✓ Mode = recipe; pieces are reusable.
- **L15** ✓ Validity rules per piece, checked at recipe save + pipeline build.
- **L17** ✓ Hybrid γ: setting controls availability, recipe controls inclusion.
- **L18** ✓ `VadAutoStopEnabled` becomes piece-inclusion; migration adds/removes `VadController` from default recipe.
- **L19** ✓ `Parameter<T>` Codable enum with cascade resolution centralized.
- **L20** ✓ Three role protocols, no umbrella.

## Architecture sketch

`PersonalScribeCore` owns vocabulary types: `ModelLifecycle`, `Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`, `Processor`/`CaptureController`/`OutputSink` role protocols, `WorkflowMode` (renamed `ModeDescriptor`), `Recipe`, `Parameter<T>`, `TranscriberCapabilities`. `TranscriptionResult` gains optional fields.

`PersonalScribeTranscription` houses FluidAudio adapters: `ParakeetTDTAdapter` (Transcriber), `Qwen3ASRAdapter` (Transcriber), `ParakeetEOUAdapter` (StreamingTranscriber), `OfflineDiarizerAdapter` + `LSEENDDiarizerAdapter` (SpeakerDiarizer). Each adapter wraps one FluidAudio manager class, owns its load/run/progress.

`PersonalScribeSession` houses pipeline composition: `EngineProvider` (renamed `ModelBoundTranscriberProvider`) with shared per-descriptor cache + lifecycle plumbing under typed-accessor facade. `RecipeBuilder` resolves a `WorkflowMode` into an instantiated pipeline. `DiarizingTranscriberProcessor` is a shared composable Processor wrapping `SpeakerDiarizer` + `Transcriber` per-turn dispatch (Q2 option b). `SessionPipelineOrchestrator` becomes recipe-driven: walks the resolved Processor list and CaptureController list; outputs flow to OutputSinks.

Data flow (capture mode):
1. `CaptureController` set drives stop. AudioCapturer streams PCM.
2. `Processor` chain runs in declared order. `DiarizingTranscriberProcessor` (when included) consumes raw PCM, emits `TranscriptionResult` enriched with speaker turns.
3. Plain ASR mode skips that processor entirely.
4. `OutputSink` set fires (clipboard, paste, persistence).

Streaming mode shares the recipe model; Processors emit deltas on an `AsyncStream<ProcessorEvent>` instead of returning a single result.

Key seams: (a) `EngineProvider.transcriber(for:)` etc. are the only types that know about FluidAudio; (b) `Recipe` is the single unit of validity-checked pipeline shape; (c) `Parameter<T>.resolve(in:)` is the only place cascade resolution lives; (d) `TranscriberCapabilities` is the only place feature-gating consults.

## File / type list

| filename | role | summary |
|---|---|---|
| `Core/Protocols/ModelLifecycle.swift` | new protocol | `prepare`, `modelDownloadProgress` |
| `Core/Protocols/Transcriber.swift` | rename + edit | composes `ModelLifecycle`; batch transcribe |
| `Core/Protocols/StreamingTranscriber.swift` | new protocol | `process(stream:)` returns `AsyncStream<TranscriberEvent>` |
| `Core/Protocols/SpeakerDiarizer.swift` | new protocol | update-oriented `AsyncStream<DiarizationUpdate>` |
| `Core/Protocols/Processor.swift` | new role | audio (+priors) → structured output |
| `Core/Protocols/CaptureController.swift` | new role | signals stop |
| `Core/Protocols/OutputSink.swift` | new role | output → side effects |
| `Core/Models/WorkflowMode.swift` | rename `ModeDescriptor` | adds `Recipe` field |
| `Core/Models/Recipe.swift` | new | role-specific lists + `[Parameter<Any>]` |
| `Core/Models/Parameter.swift` | new | Codable enum: `.override(T)` / `.global(SettingKey)` |
| `Core/Models/TranscriberCapabilities.swift` | new | static-let per adapter; fields: `providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`, `providesSpeakerTurns` |
| `Core/TranscriptionResult.swift` | edit | adds `confidence?`, `tokenTimings?`, `performance?`, `speakerTurns?`, `ctcDetectedTerms?` |
| `Core/Models/Selection/TranscriptionEngine.swift` | edit | drop `kind` from descriptors; add `var kind: ModelKind` |
| `Transcription/ParakeetTDTAdapter.swift` | rename `ModelAwareFluidAudioTranscriber` | `Transcriber` conformance |
| `Transcription/Qwen3ASRAdapter.swift` | new | `Transcriber`; capabilities = text-only |
| `Transcription/ParakeetEOUAdapter.swift` | new | `StreamingTranscriber` |
| `Transcription/OfflineDiarizerAdapter.swift` | new | `SpeakerDiarizer` (batch path) |
| `Transcription/LSEENDDiarizerAdapter.swift` | new | `SpeakerDiarizer` (streaming + batch) |
| `Session/EngineProvider.swift` | rename + edit | typed accessors + shared cache + lifecycle |
| `Session/Pipeline/DiarizingTranscriberProcessor.swift` | new | per-turn fusion (L12) |
| `Session/Pipeline/RecipeBuilder.swift` | new | mode → pipeline; runs validity |
| `Session/Pipeline/Validity/RecipeValidator.swift` | new | declarative rules |
| `Session/Recipes/BuiltInRecipes.swift` | new | dictation, meeting, streaming |
| `Session/Recipes/RecipeStore.swift` | new | JSON load/save under `AppConfig.baseDirectory()/recipes/` |
| `Session/Migration/VadPreferenceMigrator.swift` | new | one-shot migration of `VadAutoStopEnabled` |
| `Session/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` | edit | recipe-driven; queries `TranscriberCapabilities` |

## Migration impact

Codable: `ModelDescriptor` decodes legacy `kind` field but ignores it; encoders stop emitting it. Catalog construction stops passing `kind:`. ~6 catalog tests assert via engine→kind; rewritten in same commit.

`ModelBoundTranscriberProvider` rename + signature change: tests using `transcriber(for:)` continue working (signature unchanged); new accessors added alongside.

`VadAutoStopEnabled = false` users: launch-time `VadPreferenceMigrator` reads pref, removes `VadController` from the user's stored default Recipe (or skips if no stored recipe — built-in default already has it), writes a one-shot bool `VadPreferenceMigrated_v1` to UserDefaults. Other globals audited: `AutoPasteEnabled`, `ClipboardRestoreEnabled`, `MuteOutputWhileRecording`. `AutoPasteEnabled` becomes `PasteOutputSink` inclusion; `ClipboardRestoreEnabled` becomes a `ClipboardOutputSink` parameter (cascade); `MuteOutputWhileRecording` stays a global setting (acts on capture controller, not piece-inclusion). All migrations run once at first session-init access of `RecipeStore`.

`ModelKind.isEnabled` flips: streamingASR + diarization → `true`. AI Models tab unfilters those rows automatically.

## Test seam shape

Adapter unit tests: each adapter has a fixture FluidAudio model directory; tests assert capability declarations + result shape mapping (Parakeet → full metadata; Qwen3 → text-only nils). Mock FluidAudio by isolating `MLModel(contentsOf:)` behind an init param (already the pattern for parakeet).

`EngineProvider` test double: in-memory `FakeAdapter` conforming to all three output protocols selectively; tests assert engine→adapter dispatch + cache identity (calling twice returns same instance).

`RecipeBuilder` tests: synthetic Recipe with `FakeProcessor`/`FakeCaptureController`/`FakeOutputSink` doubles asserts pipeline ordering and validity-rule rejection. `RecipeValidator` tested directly with declarative rule cases.

`DiarizingTranscriberProcessor` tests: feed scripted `SpeakerDiarizer` events + scripted `Transcriber` results; assert per-turn dispatch ordering + correct `speakerTurns` field on `TranscriptionResult`.

`Parameter<T>` Codable round-trip + cascade resolution tests; SwiftUI binding tested via view-model exposure.

`VadPreferenceMigrator` test: seed UserDefaults with legacy values + stored recipe, run migrator, assert recipe mutation + idempotency flag.

Manual verification per Ninimma testing discipline: meeting recipe end-to-end (record → diarize → transcribe-per-turn → paste).

## Open questions remaining

- **Streaming `Processor` event type unification** — needs main-session decision. Whether `Processor.process` returns `AsyncStream<ProcessorEvent>` always (uniform) or splits by pipeline shape into batch (`async throws -> Output`) and streaming (`AsyncStream`). Uniform stream is simpler; batch return is cheaper. Lean: uniform, but flag.
- **`Parameter<T>` resolution timing** — propose lazy on first access during pipeline build (single-shot), cached on the resolved piece. Eager at recipe-save would re-evaluate on every global-setting change. Confirm direction.
- **`OfflineDiarizerManager` vs `LSEENDDiarizer` deletion candidate** — deferred per CHECKLIST. Adapter list above keeps both; main session decides whether `OfflineDiarizerAdapter` lands or LSEEND batch-mode subsumes it.
