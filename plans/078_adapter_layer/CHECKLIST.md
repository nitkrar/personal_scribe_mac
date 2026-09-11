# #078 — Adapter layer for non-Parakeet model families

Decisions log for the design discussion. Single source of truth for locks, open questions, renames, and follow-ups. **Subagents drafting plan options must respect every L-numbered lock.**

## Vocabulary (locked, verbatim — no synonym invention)

| Term | Meaning | Notes |
|---|---|---|
| **Mode** | Workflow preset. User-facing recipe of pipeline shape + processors + capture controllers + output sinks + per-mode parameters. | Bare "Mode" is reserved for this. Other "*Mode" types renaming separately. |
| **Setting** | Global preference. Tunes behavior of pieces, never adds/removes them. Acts as default value for piece parameters under the cascade. | |
| **Pipeline shape** | `batch \| streaming`. The flow type. | Mode declares this. |
| **Processor** | Consumes audio (or audio + prior structured output), emits structured output. | Examples: ASR, diarization, voice-ID labeling. |
| **Capture controller** | Signals "stop now." | Examples: VAD, manual hotkey release. |
| **Output sink** | Consumes final structured output, performs side effects. | Examples: clipboard, paste, SQLite history. |
| **Adapter** | Per-engine FluidAudio glue. One per FluidAudio manager class. | |
| **Engine** | Backend identity (internal). | `parakeetTDT \| qwen3ASR \| parakeetEOU \| diarization`. |
| **Kind** | User-facing capability category. **Derived from engine, not stored.** | `asr \| streamingASR \| diarization \| vad \| tts`. |
| **Provider** | The SDK that delivers a model. | FluidAudio for everything today. |
| **Vendor** | The model's origin / who made the weights. | NVIDIA (Parakeet), Qwen team (Qwen3), pyannote+WeSpeaker (diarization). |
| **Recipe** | Informal synonym for Mode (the declarative spec). | Use "Mode" in protocol/type names; "recipe" in prose. |
| **Piece** | Informal shorthand for any pipeline element. | Formal types are role-specific (Processor, CaptureController, OutputSink). **No `Piece` umbrella protocol.** |
| **Parameter cascade** | `per-mode override > global setting > hardcoded default`. | Implemented as `Parameter<T>` (per L19). |

## Locks

### Concept identity (no duplication)

- **L1** — One canonical model identity = `ModelDescriptor`. No parallel registry, no duplicated metadata.
- **L2** — `engine` is canonical; `kind` is **derived**. Remove `kind` field from `ModelDescriptor`; add computed `var kind: ModelKind` on `TranscriptionEngine`. Single source of truth.
  - *Consequence*: catalog descriptors no longer pass `kind:` at construction; tests that pin `kind` separately rewrite to assert via the engine→kind mapping.
- **L6** — Active selection stays `[ModelKind: descriptorID]` (per #024.10). Pipeline picks stages by querying active-per-kind.
- **L8** — No backend-agnostic abstraction beyond FluidAudio today. Adapters can be FluidAudio-specific.
  - *Consequence*: future backends are a separate refactor with concrete shape to design against. Don't pre-generalize.

### Architecture

- **L3** — Lifecycle (`prepare`, `modelDownloadProgress`) is its own protocol (`ModelLifecycle`). Output protocols compose it. Don't bundle universal lifecycle with output shape.
- **L4** — One adapter per FluidAudio manager class. Each adapter owns the load + run path for its manager. **No shared `FluidAudioRuntimeVariant` enum across families.**
  - *Consequence*: today's `FluidAudioRuntimeVariant` collapses into a parakeet-internal detail of the parakeet adapter (or is deleted entirely).
- **L7** — Engine→adapter dispatch lives at the provider boundary. Provider exposes typed accessors per output shape.
- **L9** — Three output protocols: `Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`. **Don't unify under one polymorphic protocol.**
  - *Consequence (evidence-backed)*: agent 2 confirmed three FluidAudio managers have no common return shape — `AsrManager` returns rich `ASRResult`, `Qwen3AsrManager` returns plain `String`, `StreamingEouAsrManager` is callback-driven. Forcing unity = nil-fields everywhere or generic-soup.
- **L10** — `SpeakerDiarizer` mirrors FluidAudio's `Diarizer` shape (update-oriented: provisional + finalized + terminal). **One protocol carries both batch and streaming diarization.**
  - *Consequence (evidence-backed)*: agent 3 confirmed FluidAudio already ships LSEEND + Sortformer streaming diarization with this update-oriented shape. Vendor-side unification means we don't duplicate.
- **L11** — `TranscriptionResult` carries optional metadata fields (`confidence?`, `tokenTimings?`, `performanceMetrics?`, `ctcDetectedTerms?`, etc.). Each adapter declares `TranscriberCapabilities`. Features query capability before exposing UI.
  - *Consequence*: Qwen3 fills only `text`; Parakeet fills the rest. Features dependent on timings disable themselves when active model lacks the capability. Settings UI surfaces "Qwen3 selected — these features unavailable: …" for transparency.
- **L12** — Fusion rule for diarization+ASR: **diarize-then-transcribe-per-turn**. Same rule for batch (all turns finalize at once) and streaming (turns finalize incrementally as audio arrives).
  - *Consequence (evidence-backed)*: agent 1 confirmed FluidAudio doesn't ship a fused pattern; ASR's public API exposes token timings (not word timings), so ASR-then-align is technically harder. Per-turn dispatch is the cleaner data flow and unified across batch/streaming.
- **L13** — `ModelLifecycle` separate protocol; all three output protocols compose it. Don't duplicate `prepare()` and `modelDownloadProgress()` across the three.

### Pipeline composition (Option C — reusable pieces)

- **L14** — Pipelines are **recipes** composed of reusable pieces. Mode = recipe declaring which capture controllers + processors + output sinks + parameter overrides apply.
  - *Consequence*: shared concerns (capture, error handling, lifecycle) live once in shared pieces. New mode = new recipe class, no new full-pipeline class. Bug fix in a piece propagates to every mode using that piece.
- **L15** — Pieces have validity rules (pipeline shape + cross-piece compatibility). Enforce **runtime + UI**: UI prevents invalid combos for built-in modes; runtime catches user-defined recipes loaded from disk that go stale across app updates.
  - *Consequence*: validity check fires at recipe save AND at session start. Failure mode: clear error, fall back to default mode.
- **L20** — Three roles for pipeline pieces: **Processor** (audio → structured output), **Capture controller** (signals stop), **Output sink** (output → side effects). Mode recipe holds three role-specific lists, **no umbrella `Piece` protocol**.

### Behavior

- **L17** — Cross-cutting opt-ins use **hybrid (γ)**: a global setting controls *availability* (e.g., "voice-ID enrolled & ready"); a processor or piece in the mode recipe controls *use*.
  - *Consequence*: enabling voice-ID globally just makes it *available* to modes. Each mode declares whether to include `VoiceIDLabeler` in its recipe. Settings can't silently inject behavior into a mode that didn't ask for it.
- **L18** — `VadAutoStopEnabled` boolean preference is **legacy** under composable modes. VAD-on-or-off becomes piece-inclusion (mode declares whether `VadController` is in the recipe). VAD parameters (silence threshold, warning flag, notification flag) follow L19's cascade.
  - *Consequence*: migration story — existing `VadAutoStopEnabled = false` users → their default mode loses `VadController`. Settings UI's "Auto-stop after silence" toggle either disappears or becomes a meta-default for new modes.
- **L19** — **Parameter cascade is a required design element**. Unified type (suggested name: `Parameter<T>`) holds either an explicit override value or a reference to a global preference key. Resolution rule: per-mode override > global setting > hardcoded default. Resolution lives in one place, not per-piece.
  - *Consequence*: mode recipes store `Parameter<TimeInterval>` for VAD threshold etc., not bare `TimeInterval?`. Subagents must propose this type's exact shape (Codable, resolution timing, integration with SwiftUI bindings).

### Synthesis-derived locks (round-1 review resolved 2026-04-25)

- **L25** — **Descriptor binding is eager-at-pipeline-build.** `ActiveModelService.activeDescriptor(for: kind)` resolves once when `RecipeBuilder` constructs a pipeline at session start; the bound descriptor cannot change for the duration of the session. Mid-session `ActiveModelService.setActive` does NOT affect the in-flight session — takes effect on the next session. Mirrors the existing `VadPreferences` snapshot-once pattern (`SessionPipelineOrchestrator.swift:627`).
  - *Consequence*: Modes UI must not claim "active immediately" for mid-session swaps. Tests verify mid-session `setActive` is a no-op for the running session.
- **L26** — **`DiarizedTurnTranscriptionProcessor` audio-slicing contract**:
  - **Inter-turn gaps** → drop, no ASR call. Diarizer is the authority on "who was speaking."
  - **Overlap regions** → ASR each turn end-to-end including the overlap zone. Two labeled transcripts emitted; overlap zone may produce partial/garbled text. Garbled-but-captured > silent loss. Optional `[multiple speakers]` cosmetic marker.
  - **Provisional turns** → only finalized turns trigger ASR. Streaming-with-diarization is segment-at-a-time output, not realtime typing — text appears once a turn finalizes. UI may surface non-text "speaker_X talking…" indicator during the wait.
  - *Consequence*: realtime typing of diarized output is out of scope (would require Ninimma-owned editor surface, not paste-to-other-app).
- **L27** — **VAD migration uses Settings-toggle-becomes-recipe-builder pattern.** Settings UI's "Auto-stop after silence" toggle reads/writes the active recipe's `CaptureController` list via `WorkflowModeRegistry`. Visually unchanged. Underneath: legacy `VadAutoStopEnabled` preference is migrated once at first launch (preserves user's prior choice into recipe shape), the toggle then mutates recipes directly. Same pattern for `AutoPasteEnabled`, `ClipboardRestoreEnabled`. `MuteOutputWhileRecording`, `BackgroundLaunchPreference` remain global (orthogonal to pieces).
  - *Consequence*: no user-visible regression; coupling Settings UI to `WorkflowModeRegistry` is acceptable (~1 file). When Modes editor ships, the legacy toggles become redundant and can be removed.

## Open questions (→ for subagents to propose plan options)

- **→** Concrete protocol method signatures for `Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`. Async/throws shape, return type vs stream-of-events, error propagation.
- **→** Where the diarize-then-transcribe-per-turn fusion logic lives. Three options: (a) inside a `MeetingPipeline`-style recipe-specific class; (b) shared `DiarizingTranscriberCoordinator` composable piece referenced by recipes; (c) in the orchestrator with mode-driven branching. **L14 leans toward (b)** — composable, bug-equality across modes. Subagents propose final shape with concrete file structure.
- **→** Provider API surface — exact signatures for `transcriber(for:)`, `streamingTranscriber(for:)`, `diarizer(for:)`. **Shared cache structure underneath** (per-descriptor adapter cache, shared lifecycle wiring, shared download/delete paths) — type-narrowing accessors are compile-time guards, not divergent code paths.
- **→** Recipe serialization format. Built-in modes hardcoded in code; user-defined modes serialize where? UserDefaults, JSON file in `AppConfig.baseDirectory()`, SQLite?
- **→** `TranscriberCapabilities` exact field set. Per L11 — which capabilities are queried by which features? Concrete list: `providesTokenTimings`, `providesConfidence`, `providesPerformanceMetrics`, `providesCustomVocabulary`, others?
- **→** `Parameter<T>` exact shape per L19 — Codable for serialization, resolution timing (eager at piece-construction vs lazy on access), SwiftUI binding integration, how a UI distinguishes "from global" vs "overridden for this mode."
- **→** Validity-rule enforcement specifics per L15 — where rules live (per-piece declared? central registry? type-level?), when checked (save / build / load / session-start), failure UX details.
- **→** Migration plan for existing global feature toggles that become piece-inclusion under L18 (`VadAutoStopEnabled` is the named one; check if there are others).

## Renames piggybacked into the parallel session's worktree batch

- `Transcribing → Transcriber` — Sequence A (protocol rename, serializes first).
- `AudioCapturing → AudioCapturer` — Sequence A (protocol rename, serializes first).

Both renames touch protocol declaration + every conformer file + every `any X` callsite — atomic per worktree, no half-states.

## Deferred / follow-ups

- **Parameter staleness across app updates** (Hole 3 from design grilling). Pre-second-user we accept silent param-shape drift. Migration plumbing lands when shipping to a second human. Naming convention nudge: prefer explicit unit suffixes for tuning params (`silenceThresholdSeconds: TimeInterval`) to make breakage loud if the unit ever changes.
- **Backend-agnostic abstraction** (per L8). Land when a second SDK appears.
- **LSEEND streaming diarization adapter** — separate ticket. Lands when streaming diarization product use case requires it. Test offline diarization (pyannote+WeSpeaker) quality first; if sufficient, defer LSEEND indefinitely.
- **Active mode vs Active model service split** (parallel session ambiguity #8) — **resolved by L21**: WorkflowModeRegistry (active mode) is distinct from ActiveModelService (active per-kind descriptor).

## Evidence trail

- `plans/investigations/2026-04-25-078-fluidaudio-fusion-codex.md` — FluidAudio doesn't ship a fused diarization+ASR pattern; we'd be inventing the fusion. ASR public surface exposes token timings, not word timings.
- `plans/investigations/2026-04-25-078-asr-output-shapes-codex.md` — Three ASR managers return three different shapes. No common subset beyond "transcript text."
- `plans/investigations/2026-04-25-078-streaming-diarization-codex.md` — FluidAudio already ships streaming diarization (LSEEND, Sortformer). Both implement a unified `Diarizer` protocol with update-oriented output shape (`finalizedSegments`, `tentativeSegments`).
