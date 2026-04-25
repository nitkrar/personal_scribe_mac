# Ubiquitous Language

The shared vocabulary for talking about Ninimma — between contributors, agents, and the codebase. Use these terms verbatim in plans, commits, briefs, and code. When two terms compete for the same concept, the canonical column wins; the alias column lists what to **avoid**.

> Regenerated 2026-04-25 after the 8-rename batch + ModeDescriptorTests follow-up landed on trunk. The rename batch eliminated most of the prior ambiguity flags (bare "Mode" overload, `ModeDescriptor` vs `ModelDescriptor`, `Recording` state-vs-stage-vs-verb). Remaining flags are at the bottom; new design vocabulary not yet in code lives in **§ Target vocabulary**.

## App identity

| Term                | Definition                                                                                  | Aliases to avoid                          |
| ------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Ninimma**         | The user-facing display name of the app                                                     | Seshat, PersonalScribe (legacy code-only) |
| **PersonalScribe**  | The Swift identifier prefix for every module, type, and target                              | Seshat-prefixed names, Ninimma-prefixed types |
| **Bundle**          | The macOS app bundle whose identifier is `com.nitkrar.personal_scribe`                      | Application package                       |
| **Pillar**          | One of the three product axes — **Dictation**, **Notes**, **Intelligence**                  | Feature area, vertical, layer             |

## Session lifecycle

| Term                | Definition                                                                                  | Aliases to avoid                          |
| ------------------- | ------------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Session**         | One capture-to-output cycle, from hotkey press to delivered transcript                      | Run, instance, take                       |
| **Session state**   | The discrete lifecycle phase a session is in (`idle`/`capturing`/`holdRecording`/`transcribing`/`completed`/`shortExit`/`error`) — note `.capturing` (post-rename), no longer `.recording` | Status, phase, `.recording` case label   |
| **Capturing**       | The active phase where the microphone is buffering audio (`SessionState.capturing`)         | Recording-state (the `SessionState` case is now `.capturing`); the user-facing verb is still "record" |
| **Hold-to-record**  | The gesture variant where the hotkey is held down and release ends the session              | Push-to-talk, momentary mode              |
| **Toggle-record**   | The gesture variant where a single press starts and the next press stops                    | Latched mode, click-to-record             |
| **Transcribing**    | The post-capture phase where buffered audio is run through the active voice model           | Processing, recognizing                   |
| **Stop**            | End capturing and run transcription on the buffered audio                                   | Finish, end                               |
| **Cancel**          | End capturing and discard audio without transcribing                                        | Abort, kill (in user-facing copy)         |
| **Short exit**      | A non-error early termination because the recording was too short to be worth transcribing  | Quick cancel, abort, stub session         |

## Capture & VAD

| Term                  | Definition                                                                                | Aliases to avoid                          |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Capture**           | The pipeline step (`PipelineStepID.capture`) that turns microphone input into a stream of `PCMBuffer`s | Audio input, mic stream                   |
| **PCM buffer**        | A frame of normalized 16 kHz mono float audio passed between pipeline steps               | Audio chunk, sample buffer                |
| **VAD**               | Voice activity detection — the FluidAudio `Silero` model that emits speech-start/end events | Speech detection, silence detection       |
| **Speech ended**      | The VAD event indicating the speaker has fallen silent                                    | Silence detected, end-of-speech           |
| **Speech resumed**    | The VAD event indicating the speaker started talking again after a pause                  | Re-engagement, speech restart             |
| **Auto-stop**         | The optional behaviour where the session stops itself after VAD detects sustained silence | Silence stop, idle stop                   |
| **Grace period**      | The window between `speechEnded` and the auto-stop firing, during which `speechResumed` cancels it | Wait timer, hold-off, debounce            |
| **Audio level**       | A normalized `[0, 1]` loudness value broadcast during capturing for waveform visualisation | Volume, amplitude, gain                   |
| **Audio capturer**    | A type conforming to the `AudioCapturer` protocol — produces a `PCMBuffer` stream         | `AudioCapturing` (old name, removed)      |

## Models & catalog

| Term                    | Definition                                                                                | Aliases to avoid                          |
| ----------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Model**               | A downloadable AI artifact (weights + config) loaded at runtime from the catalog          | AI module, weights bundle                 |
| **Model descriptor**    | The metadata record describing one model — id, repo, kind (today: stored), engine, performance | Model record, model entry                 |
| **Model kind**          | The capability category of a model (`asr`/`streamingASR`/`diarization`/`vad`/`tts`). Today **stored** on `ModelDescriptor`; under #078 will become **derived from engine** (see Target vocab §) | Model type, model class                   |
| **ASR**                 | Automatic speech recognition — the only `ModelKind` with a working transcriber today      | "Voice model" (acceptable as user-facing alias only) |
| **Active model**        | The model currently selected for a given `ModelKind` slot, persisted in `ActiveModelService` | Default model, current model              |
| **Catalog**             | The `BuiltInModelCatalog` — the static registry of every model the app knows about        | Registry, library, list                   |
| **Engine**              | Backend identity (internal — `parakeetTDT`/`parakeetEOU`/`qwen3ASR`/`diarization`)        | Backend, runtime, family                  |
| **Adapter**             | Per-engine FluidAudio glue. **One per FluidAudio manager class** (#078 L4)                | Driver, wrapper, plug-in                  |
| **Provider**            | The SDK that delivers a model. FluidAudio for everything today                            | Vendor (different concept)                |
| **Vendor**              | The model's origin — who made the weights (NVIDIA for Parakeet, Alibaba/Qwen for Qwen3, pyannote+WeSpeaker for diarization) | Provider (different concept)              |
| **Transcriber**         | A type conforming to the `Transcriber` protocol — runs a model over `PCMBuffer`s          | `Transcribing` (old name, removed)        |
| **Download progress**   | The streamed `phase`/`fractionCompleted` snapshot emitted while a model is being fetched  | Download status, fetch progress           |

## Workflow

| Term                   | Definition                                                                                 | Aliases to avoid                          |
| ---------------------- | ------------------------------------------------------------------------------------------ | ----------------------------------------- |
| **Workflow mode**      | A user-selectable persona (today only **Dictation**) bundling a voice model, optional LLM, and system prompt. Type: `WorkflowMode` | Bare "Mode" (always disambiguate); `ModeDescriptor` (old name, removed) |
| **Mode**               | Synonym for `WorkflowMode`. **Reserved for workflow-mode only** in code; never bare "mode" for any other concept | "Visibility mode", "output mode", etc. — those concepts have their own typed names |
| **Setting**            | A global preference that **modulates** existing pipeline pieces — never adds or removes pieces | Toggle, option (when used loosely)        |
| **Dictation mode**     | The default workflow mode: free-form speech inserted as text                               | Speech mode, default mode                 |
| **Command mode**       | The Phase 4 workflow mode for actionable requests routed through the intent classifier     | Action mode, agent mode                   |

## Pipeline

| Term                       | Definition                                                                              | Aliases to avoid                          |
| -------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Pipeline**               | The ordered sequence of steps that turns captured audio into delivered text             | Flow, chain, processing graph             |
| **Pipeline step**          | One named segment of the pipeline (`PipelineStepID`: `capture`/`transcription`/`postProcessing`/`persistence`/`output`) | Stage (reserved for central-layers refactor — `plans/central/STAGE_*.md`), phase |
| **Pipeline shape**         | The flow type — `batch` or `streaming`. Type: `PipelineShape`                           | `OutputMode` (old name, removed)          |
| **Session coordinator**    | The actor (`SessionCoordinator`) that owns the pipeline, exposes mode-specific entry points, and serialises state transitions | Controller, manager, session manager      |
| **Orchestrator**           | The pipeline actor (`SessionPipelineOrchestrator`) that drives steps + holds the snapshot stream | Pipeline, runner                          |
| **Post-processing**        | The step that strips fillers and applies basic punctuation to the raw transcription     | Cleanup, normalisation, polish            |
| **Persistence**            | The step that writes the finalised `TranscriptEntry` to the transcript store            | Saving, storage write, archival           |
| **Output**                 | The step that delivers the final text to clipboard, paste, or type-events               | Delivery, paste, send                     |

## Output delivery

| Term                  | Definition                                                                                | Aliases to avoid                          |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Output target**     | Where text lands (`OutputTarget`: `frontmostApp`/`clipboardOnly`/`selfFrontmost`)         | Destination, paste target                 |
| **Output delivery**   | How text is injected (`OutputDelivery`: `paste`/`typeEvents`/`clipboardOnly`)             | Method, mechanism                         |
| **Auto-paste**        | The behaviour of synthesising a Cmd+V into the frontmost app after capture ends           | Paste-back, paste-on-finish               |
| **Clipboard restore** | Restoring the user's pre-session clipboard contents some seconds after auto-paste         | Clipboard rollback, paste cleanup         |

## Surfaces

| Term                       | Definition                                                                              | Aliases to avoid                          |
| -------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Pill**                   | The small floating overlay window that shows session state and waveform                 | Bubble, capsule, indicator                |
| **Pill visibility**        | The user preference for when the pill is shown (`PillVisibility`: `alwaysOn`/`autoShow`/`hidden`) | `PillVisibilityMode` (old name, removed); pill mode (ambiguous) |
| **Pill style**             | The user preference for the pill's *shape* (`PillStyle`: `classic`/`mini`/`none`)       | Pill shape, pill variant, pill size       |
| **Pill appearance**        | The user preference for the pill's dark/light token set (`PillAppearance`)              | Pill colour, pill skin                    |
| **Pill visibility state**  | The runtime-derived display state of the pill (`PillVisibilityState`: `hidden`/`idle`/`recording`/…). **Note**: `PillVisibilityState.recording` is intentionally kept — refers to the *visible recording* layout, not the session state | Pill status (ambiguous with Pill visibility) |
| **Response card**          | The transient rectangular panel anchored above the pill that shows transcript or status text | Status card, toast, popover               |
| **Menu bar item**          | The `NSStatusItem` icon in the system menu bar exposing quick actions                   | Tray icon, status icon                    |
| **Unified window**         | The main settings/transcripts/permissions window that replaced the separate windows in Phase 3 | Main window, app window                   |
| **AI Models tab**          | The Settings tab that is the authoritative surface for voice + future LLM model state   | Models pane, Models page                  |

## Hotkeys & input

| Term                  | Definition                                                                                | Aliases to avoid                          |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Hotkey**            | The global keyboard shortcut configured to drive a session                                | Keybind, accelerator                      |
| **Recording hotkey**  | The hotkey bound to start/stop a session (default `opt + /`). Persisted under UserDefaults key `"RecordingHotkey"` (note: the persisted key keeps the "Recording" string for back-compat even though the session-state case is now `.capturing`) | Trigger, action key                       |
| **Tap**               | A single press-and-release of the recording hotkey                                        | Click, hit                                |
| **Hold**              | A press of the recording hotkey held past the hold threshold (300 ms)                     | Long-press, press-and-hold                |
| **Hotkey monitor**    | The component that turns raw `NSEvent`/`CGEvent` keys into `tap`/`hold`/`release` actions | Hotkey listener, key handler              |
| **Background launch preference** | The Dock-visibility / `LSUIElement` setting for app launch (`BackgroundLaunchPreference`) | `BackgroundModePreference` (old name, removed) |

## Persistence

| Term                       | Definition                                                                              | Aliases to avoid                          |
| -------------------------- | --------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Transcript**             | The persisted text record of one completed session                                      | Note (UI copy only), recording (overloaded) |
| **Transcript entry**       | The on-disk struct for one transcript: text, timestamp, duration, model id              | Note record, log entry                    |
| **Transcript repository**  | The read/write/delete API over the transcript store                                     | Notes service, history API                |
| **Transcript store**       | The SQLite + FTS5 backing store for transcripts (Phase 3+)                              | Database, notes DB                        |
| **Base directory**         | The on-disk root for app data — `~/Library/Application Support/personal_scribe/` by default | App support folder, root dir              |

## Permissions

| Term                  | Definition                                                                                | Aliases to avoid                          |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Microphone permission**       | TCC grant required to capture audio                                             | Mic access, audio permission              |
| **Input monitoring permission** | TCC grant required to observe global key events for the recording hotkey         | Hotkey permission, key access             |
| **Accessibility permission**    | TCC grant required to synthesise paste / type events into other apps             | A11y, accessibility access                |
| **Permission status**           | The state of one permission grant (`granted`/`denied`/`notDetermined`/`restricted`) | Authorization, access level               |

## Intent (Phase 4 — speculative)

| Term                  | Definition                                                                                | Aliases to avoid                          |
| --------------------- | ----------------------------------------------------------------------------------------- | ----------------------------------------- |
| **Intent**            | The classification of a transcript (`dictation`/`command`/`query`/`unknown`) used to route it post-transcription | Action class, message type                |
| **Intent classifier** | The component that maps transcript text to an `Intent`                                    | Router, classifier, NLU                   |
| **Tier**              | One of the rule / NLEmbedding / llama.cpp passes the classifier escalates through         | Layer, level, stage                       |

## Relationships

- A **Hotkey** press starts a **Session** owned by the **Session coordinator**.
- A **Session** moves through one **Session state** at a time and emits one **Pill visibility state** per transition.
- A **Session** runs through every **Pipeline step** in order; the **Capture** step produces **PCM buffers** via an **Audio capturer**, **Transcription** runs the **Active model** (resolved from the current **Workflow mode**) via an **Adapter**, and **Output** delivers via the configured **Output target** + **Output delivery**.
- The **Pill visibility** preference gates whether the **Pill** is shown; the **Pill style** and **Pill appearance** decide how it looks.
- A completed **Session** produces exactly one **Transcript** persisted by the **Transcript repository**.
- The **VAD** can fire **Auto-stop** during a **Session**, which the **Session coordinator** routes through the same `stopIfActive()` path as a manual **Stop**.
- A **Workflow mode** references one **Active model** per **Model kind**; today only `.asr` is wired through.
- An **Adapter** is owned by a single FluidAudio manager class. A **Provider** routes a `ModelDescriptor` to the right **Adapter** by **Engine**.

## Example dialogue

> **Dev:** "After the rename batch landed, what's the state when the user is mid-utterance?"

> **Domain expert:** "`SessionState.capturing`. The old label was `.recording`, but the codebase reserved 'recording' as the user-facing verb and the audio-file name. The state-machine token is now `.capturing`."

> **Dev:** "And the **Pill** still shows a 'recording' visual?"

> **Domain expert:** "Yes — `PillVisibilityState.recording` stays as-is. The pill's *visual* state is named after what the user sees ('recording'), independent of the session state-machine label. Two enums, two namespaces."

> **Dev:** "What about a workflow that's diarization-then-ASR? Two **Adapters** running in sequence?"

> **Domain expert:** "That's #078 territory — not landed yet. In the **Target vocabulary** below, that's a **Recipe** declaring two **Processors** (a `SpeakerDiarizer` and a `Transcriber`). Today only ASR is composed; multi-piece pipelines are an L14 follow-up."

## Flagged ambiguities (still open)

- **`PillVisibilityState.recording` vs `SessionState.capturing`** — different namespaces, intentionally different. The pill-visual-state case is named for what the user sees ("recording"); the session-state case is named for the runtime behavior ("capturing"). Both correct. Disambiguate by enum receiver.

- **"Recording"** still has three valid uses in this codebase: (a) user-facing verb / UI copy, (b) `PillVisibilityState.recording` case, (c) the persisted `RecordingHotkey` UserDefaults key (preserved for back-compat). It is no longer the `SessionState` case.

- **"Provider" vs "Vendor"** — both are model-related but distinct: **Provider** = the SDK that loads/runs the model (FluidAudio today); **Vendor** = who made the weights (NVIDIA, Qwen team, pyannote). Always say one or the other in full.

- **Active mode vs Active model** — separate services. **Active model** = currently selected `ModelDescriptor` per `ModelKind` (`ActiveModelService`). **Active mode** = currently selected `WorkflowMode` (today via `AppStoreActiveModeProviding`; will become a dedicated `WorkflowModeRegistry` under #078 per CHECKLIST L6+L14). Never share "active" framing without the noun.

- **"Step" vs "Stage" vs "Phase"** — three textually similar concepts in this project, kept disjoint: **Step** = pipeline-internal segmentation (`PipelineStepID`). **Stage** = central-layers refactor work-units (`plans/central/STAGE_*.md`). **Phase** = product-milestone roadmap (Phase 1/2/3/4) AND commit-tag prefix (`phase-N step N.M:`). Don't cross them.

- **"Transcribing"** can refer to (a) the `SessionState.transcribing` case, (b) the `Transcription` pipeline step, (c) the user-visible status caption ("Transcribing…"). Same word, three load-bearing meanings — disambiguate by context (state machine / pipeline / UI).

## Target vocabulary (not yet in code)

These are #078-locked terms that **describe planned types and modules from `plans/078_adapter_layer/CHECKLIST.md`**. They are not in the current codebase. When #078 implementation lands, this section migrates upward into the live tables and this section either empties or hosts the next batch of design vocab.

| Term                       | Planned type / location                                                                  | Definition (per #078 CHECKLIST)                                                |
| -------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------ |
| **Recipe**                 | Type TBD; declared by `WorkflowMode`. Module: `PersonalScribeCore`                        | Informal synonym for `WorkflowMode` — the declarative spec of a pipeline (capture controllers + processors + output sinks + parameters). Use "Mode" for type names; "recipe" in prose |
| **Processor**              | `protocol Processor`. Module: `PersonalScribeCore`                                       | Consumes audio (or audio + prior structured output), emits structured output. Examples: ASR, diarization, voice-ID labeling. Per-role protocol — no umbrella `Piece` |
| **Capture controller**     | `protocol CaptureController`. Module: `PersonalScribeCore`                               | Signals "stop now." Examples: VAD, manual hotkey release. Per-role protocol  |
| **Output sink**            | `protocol OutputSink`. Module: `PersonalScribeCore`. (`PipelineOutputSink` exists today as the pipeline's text-delivery sink — different thing; the new `OutputSink` is the role-protocol for any side-effect consumer.) | Consumes final structured output, performs side effects. Examples: clipboard, paste, SQLite history. Per-role protocol |
| **Piece**                  | Informal only — **no `Piece` umbrella protocol** (L20)                                   | Shorthand for any pipeline element. Formal types are role-specific            |
| **Streaming transcriber**  | `protocol StreamingTranscriber: ModelLifecycle`. Module: `PersonalScribeCore`            | Event-stream variant of `Transcriber` for streaming ASR (parakeetEOU). Don't unify with `Transcriber` (L9)        |
| **Speaker diarizer**       | `protocol SpeakerDiarizer: ModelLifecycle`. Module: `PersonalScribeCore`                 | Per-turn speaker assignment; mirrors FluidAudio's update-oriented `Diarizer` shape (provisional + finalized + terminal). One protocol carries batch and streaming (L10) |
| **Model lifecycle**        | `protocol ModelLifecycle`. Module: `PersonalScribeCore`                                  | `prepare()` + `modelDownloadProgress()` — composed by all output protocols (`Transcriber`, `StreamingTranscriber`, `SpeakerDiarizer`). Don't duplicate per protocol (L3+L13) |
| **Transcriber capabilities** | `struct TranscriberCapabilities`. Module: `PersonalScribeCore`                         | Per-adapter capability set (e.g. `providesTokenTimings`, `providesConfidence`). Features query before exposing UI (L11)         |
| **Parameter cascade**      | `Parameter<T>`. Module: `PersonalScribeCore` (suggested name; final TBD)                 | Resolution rule: **per-mode override > global setting > hardcoded default**. One unified type, one resolution site, no per-piece logic (L19) |
| **Engine→Kind mapping**    | `var kind: ModelKind` computed on `TranscriptionEngine`. Module: `PersonalScribeCore`    | `kind` becomes derived from `engine`, no longer stored on `ModelDescriptor` (L2). Removes one stored-vs-derived consistency burden |
| **Workflow mode registry** | `WorkflowModeRegistry` service. Module: `PersonalScribeSession`                          | Distinct service from `ActiveModelService`. Owns "active mode" state separately from "active per-kind model" state (L6+L14) |
| **Model-bound processor provider** | `ModelBoundProcessorProvider`. Module: `PersonalScribeSession`                   | Engine→adapter dispatch + shared cache (L7). Replaces today's `ModelBoundTranscriberProvider`/`*Providing` pair |
| **Recipe builder**         | TBD. Module: `PersonalScribeSession`                                                     | Composes a `WorkflowMode`'s declared pieces into a runnable pipeline. Validates piece compatibility per shape at recipe save + pipeline build (L15) |

### Architectural rules (#078 locks worth remembering as vocabulary scaffolding)

- **L4** — One adapter per FluidAudio manager class. No shared `FluidAudioRuntimeVariant` enum across families. Today's enum collapses into a parakeet-internal detail.
- **L8** — No backend-agnostic abstraction beyond FluidAudio today. Adapters can be FluidAudio-specific. Second-SDK abstraction lands as a separate refactor.
- **L9** — Three output protocols stay separate. Don't unify into one polymorphic protocol (the three FluidAudio managers return three incompatible shapes — `ASRResult` vs `String` vs callback-driven).
- **L12** — Diarization+ASR fusion = **diarize-then-transcribe-per-turn**. Same rule for batch and streaming.
- **L14+L20** — Pipelines are recipes; recipes are three role-specific lists (Processor / Capture controller / Output sink). No mode-specific orchestrator branching.
- **L17** — Cross-cutting opt-ins use **hybrid (γ)**: global setting controls *availability*, mode recipe controls *use*.

## Re-running this skill

When #078 implementation lands (or the next batch of vocab work):

1. Read this file.
2. Promote any **Target vocabulary** rows whose types now exist into the live tables.
3. Add new terms surfaced by implementation.
4. Refresh the example dialogue with one or two of the newly-live terms in natural use.
5. Re-flag any new ambiguities — especially anywhere a new noun gets reused across subdomains.
6. Re-confirm or sunset the still-open ambiguities under "Flagged ambiguities."
