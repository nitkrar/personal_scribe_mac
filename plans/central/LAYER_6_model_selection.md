# Layer 6 - Model selection

## Critical discipline
> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists
Model selection is still effectively single-model. [`Sources/SeshatCore/ModelRegistry.swift:25`](../../Sources/SeshatCore/ModelRegistry.swift) registers one voice model, [`Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25`](../../Sources/SeshatTranscription/FluidAudioInferenceClient.swift) hardcodes `AsrModels.load(... version: .v2)`, and [`Sources/SeshatAppKit/Composition/AppComposition.swift:15`](../../Sources/SeshatAppKit/Composition/AppComposition.swift) builds one fixed `FluidAudioTranscriber()` for the whole process. That blocks the parked 3.F second-model work, prevents a v3 default rollout, and means the app cannot swap models without process-level rewiring.

The UI side is equally scattered. [`Sources/SeshatCore/ModeDescriptor.swift:6`](../../Sources/SeshatCore/ModeDescriptor.swift) stores raw `voiceModelID` / `aiModelID` strings, [`Sources/SeshatAppKit/Settings/ModesTab.swift:27`](../../Sources/SeshatAppKit/Settings/ModesTab.swift) resolves the voice label from `ModelRegistry` inline, [`Sources/SeshatAppKit/Components/ModeCard.swift:16`](../../Sources/SeshatAppKit/Components/ModeCard.swift) takes two loose strings, and [`Sources/SeshatAppKit/Onboarding/OnboardingView.swift:122`](../../Sources/SeshatAppKit/Onboarding/OnboardingView.swift) hardcodes one marketing label. Layer 6 introduces a single `@MainActor` service and a single `ActiveModelDescriptor` so storage, transcription, SwiftUI, and the menu bar stop inventing their own model-selection representation.

## Observed current spread
| File | Line(s) | What lives there |
|---|---|---|
| `Sources/SeshatCore/ModelRegistry.swift` | 3-52 | `TranscriptionEngine`, `ModelDescriptor`, one registered descriptor, default model ID, and ID lookup helper. |
| `Sources/SeshatCore/ModeDescriptor.swift` | 3-38 | Mode rows carry raw `voiceModelID` and optional `aiModelID`; default mode points at `ModelRegistry.defaultModelId`. |
| `Sources/SeshatCore/Config.swift` | 7-10, 57-63 | Deprecated `modelId` shim plus model-directory helper still tied to the old fixed-descriptor world. |
| `Sources/SeshatCore/Protocols.swift` | 31-35, 42-65 | `Transcribing` and `ModelDownloadProgress`, the public seams Layer 6 must preserve. |
| `Sources/SeshatTranscription/FluidAudioInferenceClient.swift` | 5-28 | Inference client loads models from disk with a hardcoded `.v2` runtime version. |
| `Sources/SeshatTranscription/FluidAudioTranscriber.swift` | 12-52, 97-150, 239-260 | Transcriber is descriptor-bound at init time, exposes `activeModelId`, owns download/load flow, and resolves its model directory from the fixed descriptor. |
| `Sources/SeshatTranscription/FluidAudioModelDownloader.swift` | 4-96 | Downloader is descriptor-bound and writes model artifacts into the descriptor directory. |
| `Sources/SeshatSession/SessionCoordinator.swift` | 28-38, 103-113, 138-158, 198-203 | Coordinator owns one injected `Transcribing` instance for prepare, download progress, and transcription. |
| `Sources/SeshatAppKit/Composition/AppComposition.swift` | 10-25 | Process-wide composition creates one `FluidAudioTranscriber()` with implicit default model wiring. |
| `Sources/SeshatAppKit/Settings/AIModelsTab.swift` | 5-45 | Read-only tab resolves the default descriptor from `ModelRegistry` and labels it "Current". |
| `Sources/SeshatAppKit/Settings/ModesTab.swift` | 5-43 | Modes tab resolves voice model names from `ModelRegistry` and AI labels directly from `ModeDescriptor.aiModelID`. |
| `Sources/SeshatAppKit/Components/ModeCard.swift` | 3-109 | Mode card accepts loose `voiceModel` / `aiModelPreset` strings instead of a shared selection value. |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | 7-27, 56-97 | Menu-bar scene model observes coordinator state and download progress only; it has no current-model source. |
| `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift` | 65-135 | Menu model only carries an `activeModeName` header, with no current-model indicator. |
| `Sources/SeshatAppKit/MenuBar/StatusItemController.swift` | 193-202 | Menu rebuild path composes the menu from session state plus permission probes only. |
| `Sources/SeshatAppKit/Onboarding/OnboardingView.swift` | 122-124 | Onboarding footer hardcodes `Parakeet TDT 0.6B`. |
| `Tests/SeshatCoreTests/ModelRegistryTests.swift` | 4-24 | Current registry contract tests assume one v2 descriptor and a v2 default. |
| `Tests/SeshatCoreTests/ModeDescriptorTests.swift` | 4-17 | Default mode test assumes `voiceModelID == ModelRegistry.defaultModelId`. |
| `Tests/SeshatTranscriptionTests/FluidAudioTranscriberCompileTests.swift` | 5-43 | Compile tests assert the old transcriber default model ID and its descriptor-bound initializer. |
| `Tests/SeshatTranscriptionTests/ModelDownloadProgressTests.swift` | 5-102 | Download-progress sequencing guard the new model-aware transcriber must preserve. |
| `Tests/SeshatTranscriptionTests/ModelDownloadFailureTests.swift` | 5-55 | Failure-path guard for resetting progress back to idle after download errors. |
| `Tests/SeshatTranscriptionTests/PrepareIdempotenceTests.swift` | 5-39 | Idempotence guard for prepare/load deduplication. |
| `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift` | 7-49 | Coordinator regression guard for stop completing while background prepare is still running. |
| `Tests/SeshatAppKitTests/Components/ModeCardTests.swift` | 11-90 | Pure UI tests for the mode card's voice/AI subtitle and active/inactive pill contract. |
| `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` | 12-35 | Menu regression guard for the current header row and item order. |
| `Tests/SeshatAppKitTests/ManualSettingsVerification.md` | 3-23 | Existing settings manual runbook; needs model-selection coverage when the UI swaps. |
| `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` | 3-25 | Manual transcription runbook is still v2-only. |
| `Tests/SeshatAppKitTests/ManualStatusItemVerification.md` | 1-26 | Manual menu-bar runbook lacks a current-model indicator check. |

Repo-wide grep note: no `SeshatActiveModelDescriptor` symbol exists in the committed tree, no active-model tuple-return helper exists, and no direct model-ID `UserDefaults` read/write exists yet. The equivalent drift is the raw two-string path at [`Sources/SeshatAppKit/Settings/ModesTab.swift:27`](../../Sources/SeshatAppKit/Settings/ModesTab.swift), [`Sources/SeshatAppKit/Components/ModeCard.swift:16`](../../Sources/SeshatAppKit/Components/ModeCard.swift), and the fixed-default shim at [`Sources/SeshatCore/Config.swift:7`](../../Sources/SeshatCore/Config.swift). Stage 3 must record those absences explicitly in the hand-off instead of claiming deleted symbols or keys that never existed.

## Proposed API / contracts
### Types (enums, structs)
- `ActiveModelDescriptor` in `Sources/SeshatCore/Models/Selection/ActiveModelDescriptor.swift`.
  - Conformances: `Codable`, `Sendable`, `Equatable`.
  - Fields:
    - `voiceModel: ModelDescriptor`
    - `aiModelID: String?`
  - Purpose: the canonical persisted and UI-facing representation of the active voice/AI pair. This replaces the split `voiceModelID` / `aiModelID` / ad hoc string formatting path now spread across `ModeDescriptor`, `ModesTab`, and `ModeCard`.
- `ModelDescriptor+Codable` and `TranscriptionEngine+Codable` extensions in new files under `Sources/SeshatCore/Models/Selection/`.
  - Purpose: allow `ActiveModelDescriptor` to persist without inventing a second storage-only model type.
- `BuiltInModelCatalog` in `Sources/SeshatCore/Models/Selection/BuiltInModelCatalog.swift`.
  - Namespace-only type exposing:
    - the current v2 descriptor
    - `parakeet-tdt-ctc-110m` with SHA `9bc92ead6e8f17eca92a869fd578ae76842b82ba`, the three-artifact fused layout, and the correct runtime mapping
    - `parakeet-tdt-0.6b-v3-coreml` as the default candidate once its exact pinned artifact metadata is supplied
  - Also exposes `defaultActiveDescriptor`.
- `FluidAudioRuntimeVariant` in `Sources/SeshatTranscription/Models/Selection/FluidAudioRuntimeVariant.swift`.
  - Value describing how a registered voice model maps to `AsrModels.load` and its artifact layout.
  - This is internal to the transcription bridge; UI and storage still traffic in `ModelDescriptor` and `ActiveModelDescriptor`.

### Protocols
- `@MainActor protocol ModelService: ObservableObject, Sendable` in `Sources/SeshatCore/Models/Selection/ModelService.swift`.
  - `var registeredModels: [ModelDescriptor] { get }`
  - `var activeDescriptor: ActiveModelDescriptor { get }`
  - `func descriptor(for mode: ModeDescriptor) -> ActiveModelDescriptor`
  - `func setActive(_ descriptor: ActiveModelDescriptor) async throws`
  - `func setActiveVoiceModel(_ id: String) async throws`
  - `func isDownloaded(_ descriptor: ModelDescriptor) -> Bool`
  - `func download(_ descriptor: ModelDescriptor, progress: @escaping @Sendable (ModelDownloadProgress) -> Void) async throws`
- `ModelBoundTranscriberProviding` in `Sources/SeshatSession/Models/Selection/ModelBoundTranscriberProviding.swift`.
  - `func transcriber(for descriptor: ModelDescriptor) -> any Transcribing`
  - Purpose: let `SessionCoordinator` resolve a transcriber per selected voice model without rebuilding the whole app shell or losing prepare/download idempotence.

### Errors
- `ModelSelectionError` in `Sources/SeshatCore/Models/Selection/ModelSelectionError.swift`.
  - Cases:
    - `unknownVoiceModelID(String)` for invalid registry selections
    - `storedSelectionNoLongerRegistered(String)` when a persisted descriptor no longer exists in the built-in catalog
  - Download and load failures continue to surface through existing shared `SeshatError.modelDownloadFailure` / `SeshatError.modelLoadFailure`.

## Proposed live implementation
Stage 1 claims only new directories:
- `Sources/SeshatCore/Models/Selection/`
- `Sources/SeshatSession/Models/Selection/`
- `Sources/SeshatTranscription/Models/Selection/`
- `Tests/SeshatCoreTests/Models/Selection/`
- `Tests/SeshatSessionTests/Models/Selection/`
- `Tests/SeshatTranscriptionTests/Models/Selection/`
- `Tests/SeshatAppKitTests/Models/Selection/`

Layer 6 Stage 1 can run in parallel with Layer 5, Layer 7, and Layer 8 Stage 1 after Layer 2 Stage 1 and Layer 3 Stage 1 have landed, because all four wave-2 layers claim disjoint new subdirectories and do not touch existing consumer files.

The concrete live service is `@MainActor final class DefaultModelService` in `Sources/SeshatSession/Models/Selection/DefaultModelService.swift`. It depends on Layer 2's `StorageLocator`, Layer 3's `Preference<ActiveModelDescriptor>`, and a transcription-side helper that knows how to download and load the currently selected voice model. It owns one `@Published private(set) var activeDescriptor`, validates selections against `BuiltInModelCatalog`, persists only through the typed `Preference` wrapper, and never reads `UserDefaults.standard` directly. If persisted data points at a removed model ID, it logs and resets to `BuiltInModelCatalog.defaultActiveDescriptor`.

The transcription bridge lives in `Sources/SeshatTranscription/Models/Selection/`. Instead of editing the current `FluidAudioInferenceClient` and `FluidAudioTranscriber` during Stage 1, add a new model-aware stack that preserves the existing downloader/progress/idempotence semantics but derives the runtime version from `FluidAudioRuntimeVariant` rather than hardcoding `.v2`. `ModelBoundTranscriberProvider` caches one model-bound transcriber per voice-model ID so `prepare()` and download progress remain deduplicated the same way `PrepareIdempotenceTests` and `ModelDownloadProgressTests` already require.

`SessionCoordinator` does not become the owner of model selection. In Stage 2 it snapshots the current voice model through `ModelService` once per recording session before background prepare starts, then reuses that same descriptor for the stop/transcribe path so progress, warm-up, and final transcription stay aligned. The next recording session sees any later model switch. AI model selection is read-only at this layer: the service persists and publishes the optional `aiModelID` alongside the voice model, but only the voice model affects transcription runtime setup.

## Migration of existing call sites
### Stage 1 - Build in parallel
Depends on Layer 2 Stage 1 and Layer 3 Stage 1 contracts being available. No existing consumer files change in this stage.

#### Step 1.1 - Add the canonical contracts and built-in catalog
| Change | Before | After |
|---|---|---|
| Add `ActiveModelDescriptor`, codable conformances, and `BuiltInModelCatalog` under `Sources/SeshatCore/Models/Selection/` plus core tests under `Tests/SeshatCoreTests/Models/Selection/`. | The app has one registry descriptor at `Sources/SeshatCore/ModelRegistry.swift:25-52`, and the active voice/AI pair is implied by raw strings in `Sources/SeshatCore/ModeDescriptor.swift:6-8`. | The layer has one canonical voice/AI selection type, a three-model catalog, and a default selection that can persist cleanly through Layer 3's `Preference<ActiveModelDescriptor>`. |

#### Step 1.2 - Add the model-aware transcription bridge and live service
| Change | Before | After |
|---|---|---|
| Add `DefaultModelService`, `ModelBoundTranscriberProviding`, a model-aware transcriber cache, and a runtime-mapping bridge under new `Sources/SeshatSession/Models/Selection/` and `Sources/SeshatTranscription/Models/Selection/` directories. | `Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27` hardcodes `.v2`, and `Sources/SeshatTranscription/FluidAudioTranscriber.swift:23-52` binds one descriptor forever. | The new layer can validate, persist, download, and prepare the selected voice model in isolation, with runtime version chosen from catalog metadata rather than from hardcoded branches. |

#### Step 1.3 - Land Stage 1 tests and fakes before any swaps
| Change | Before | After |
|---|---|---|
| Add failing-then-passing tests for default descriptor resolution, invalid stored selection fallback, model download triggering, runtime-variant mapping, and transcriber caching/deduplication. Reuse or extend test doubles under `Sources/SeshatTestSupport/` only if a new fake is required. | Current regression coverage is tied to the legacy registry/transcriber path in `Tests/SeshatCoreTests/ModelRegistryTests.swift`, `Tests/SeshatTranscriptionTests/ModelDownloadProgressTests.swift`, and `Tests/SeshatTranscriptionTests/PrepareIdempotenceTests.swift`. | Stage 1 stands on its own: the new layer builds green and proves its own persistence, runtime mapping, and deduplicated prepare/download behaviour without touching existing call sites. |

### Stage 2 - Swap
Depends on Layer 2 Stage 2 and Layer 3 Stage 2 being complete. Do one consumer-facing swap per commit.

#### Step 2.1 - Swap `SessionCoordinator` and app composition to active voice-model resolution
| Change | Before | After |
|---|---|---|
| Update `Sources/SeshatSession/SessionCoordinator.swift` and `Sources/SeshatAppKit/Composition/AppComposition.swift` to inject `ModelService` plus `ModelBoundTranscriberProviding`, and to resolve the active voice model once per recording session. Update test harnesses such as `Tests/SeshatAppKitTests/DevelopmentComposition.swift` and any compile-only app shell helpers. | `Sources/SeshatAppKit/Composition/AppComposition.swift:15-24` creates one process-wide `FluidAudioTranscriber()`, and `Sources/SeshatSession/SessionCoordinator.swift:28-38` stores one `Transcribing` instance forever. | The coordinator asks `ModelService` which voice model is active for the current session, fetches a matching transcriber from the provider, and preserves the existing prepare/progress/stop semantics while allowing future recordings to use a newly selected model. |

#### Step 2.2 - Swap the Settings model surfaces to `ActiveModelDescriptor`
| Change | Before | After |
|---|---|---|
| Update `Sources/SeshatAppKit/Settings/ModesTab.swift` and `Sources/SeshatAppKit/Components/ModeCard.swift` so the tab resolves an `ActiveModelDescriptor` through `ModelService` for each mode row and the card no longer accepts loose voice/AI strings. If `Sources/SeshatAppKit/Settings/AIModelsTab.swift` still exists when this step runs, repoint it to `ModelService.activeDescriptor` instead of `ModelRegistry.defaultModelId`. | `Sources/SeshatAppKit/Settings/ModesTab.swift:27-29` formats voice and AI labels from raw mode-row fields, and `Sources/SeshatAppKit/Components/ModeCard.swift:16-18` stores those labels separately. `Sources/SeshatAppKit/Settings/AIModelsTab.swift:8-13` resolves the default descriptor directly from `ModelRegistry`. | Settings surfaces consume the canonical `ActiveModelDescriptor`, so the view layer no longer reads `ModelRegistry`, `ModeDescriptor.voiceModelID`, or `ModeDescriptor.aiModelID` directly. |

#### Step 2.3 - Swap the menu-bar current-model indicator to `ModelService`
| Change | Before | After |
|---|---|---|
| Update `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift`, `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift` so the menu model renders a current-model indicator from `ModelService`, with unit-test updates in `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift` and any scene-model tests that snapshot menu state. | `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:65-103` only renders `activeModeName`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:196-202` rebuilds the menu without any model-selection input. | The menu bar shows the current model from the service rather than a hardcoded or mode-row-derived string, while keeping the existing permission-warning and record/stop item ordering intact. |

#### Step 2.4 - Swap the remaining hardcoded or future CRUD model consumers
| Change | Before | After |
|---|---|---|
| Update `Sources/SeshatAppKit/Onboarding/OnboardingView.swift` so the footer reads the current descriptor from injected state instead of hardcoding `Parakeet TDT 0.6B`. Also migrate any landed Manus-style Modes CRUD files to source their pickers from `ModelService.registeredModels` and to persist the chosen pair as `ActiveModelDescriptor`, not as two separate strings. | `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:122-124` hardcodes the model label. The CRUD surfaces described in `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:50-58` do not exist in the committed tree yet, but the design explicitly requires separate voice-model and AI-model pickers. | All current or newly landed SwiftUI model-selection surfaces use the service and the shared descriptor shape. If a Manus CRUD surface is still absent when this step executes, record that absence in the hand-off report instead of inventing a new file in Layer 6. |

### Stage 3 - Delete
Run only after every Stage 2 consumer above is off the legacy path and the main session confirms the global deletion pass is unlocked.

#### Step 3.1 - Delete fixed-default transcription and composition shims
| Change | Before | After |
|---|---|---|
| Remove the now-dead fixed-default path from `Sources/SeshatCore/Config.swift`, `Sources/SeshatTranscription/FluidAudioInferenceClient.swift`, `Sources/SeshatTranscription/FluidAudioTranscriber.swift`, `Sources/SeshatAppKit/Composition/AppComposition.swift`, and matching tests. | The old world still exposes `SeshatConfig.modelId` (`Sources/SeshatCore/Config.swift:7-10`), hardcodes `.v2` (`Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27`), binds `FluidAudioTranscriber` to one descriptor (`Sources/SeshatTranscription/FluidAudioTranscriber.swift:23-52`), and composes one fixed transcriber in app startup (`Sources/SeshatAppKit/Composition/AppComposition.swift:15-24`). | Only the service-backed catalog and model-aware transcriber path remain. The legacy `activeModelId` compile-time shim and the fixed-descriptor initializer path are gone. |

#### Step 3.2 - Delete direct registry lookups and the two-string UI path
| Change | Before | After |
|---|---|---|
| Remove direct `ModelRegistry` lookups and loose voice/AI string plumbing from `Sources/SeshatCore/ModeDescriptor.swift`, `Sources/SeshatAppKit/Settings/ModesTab.swift`, `Sources/SeshatAppKit/Components/ModeCard.swift`, `Sources/SeshatAppKit/Settings/AIModelsTab.swift` if it still exists, `Sources/SeshatAppKit/Onboarding/OnboardingView.swift`, and their tests. | Current UI still depends on `ModelRegistry.defaultModelId` (`Sources/SeshatCore/ModeDescriptor.swift:29`), `ModelRegistry.descriptor(for:)` (`Sources/SeshatAppKit/Settings/ModesTab.swift:41-42`), and the raw `voiceModel` / `aiModelPreset` pair (`Sources/SeshatAppKit/Components/ModeCard.swift:16-18`). | The UI consumes only service-backed `ActiveModelDescriptor` data. There is no surviving equivalent of the old tuple/string path. |

#### Step 3.3 - Delete stale tests and v2-only runbook assumptions
| Change | Before | After |
|---|---|---|
| Rewrite or remove the legacy tests and manual runbook lines that encode "one v2 default forever": `Tests/SeshatCoreTests/ModelRegistryTests.swift`, `Tests/SeshatCoreTests/ModeDescriptorTests.swift`, `Tests/SeshatTranscriptionTests/FluidAudioTranscriberCompileTests.swift`, `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md`, and `Tests/SeshatAppKitTests/ManualStatusItemVerification.md`. | Current tests and runbooks assume one v2 default model and no current-model indicator. | Regression coverage points at the new service, catalog, session-resolution seam, and menu/settings surfaces instead of the deleted legacy constants. |

## Test strategy
- Unit tests:
  - `Tests/SeshatCoreTests/Models/Selection/ActiveModelDescriptorTests.swift` for `Codable`, equality, and persistence round-trips.
  - `Tests/SeshatCoreTests/Models/Selection/BuiltInModelCatalogTests.swift` for the three registered descriptors, the 110m SHA, and the default-descriptor fallback contract.
  - `Tests/SeshatSessionTests/Models/Selection/DefaultModelServiceTests.swift` for invalid-selection fallback, `setActiveVoiceModel(_:)`, auto-download triggering, and observer updates from the `@Published` active descriptor.
  - `Tests/SeshatTranscriptionTests/Models/Selection/ModelAwareTranscriberTests.swift` for runtime-variant mapping, model-directory resolution, download retries, progress reset on failure, and prepare deduplication.
- Integration tests:
  - Add a new session-coordinator test that changes the active voice model between two recordings and proves the second recording uses the new transcriber while preserving the old `idle -> recording -> transcribing -> idle` state path.
  - Extend menu-bar tests so the current-model indicator updates without changing the permission-warning rows or action ordering.
  - Extend mode-card tests so the card renders the same subtitle and active/inactive status from an `ActiveModelDescriptor`-backed input.
- Fakes for the new protocols:
  - `FakeModelService` for AppKit tests.
  - `FakeModelBoundTranscriberProvider` for Session tests.
  - `RecordingModelDownloadClient` / `StubRuntimeVariantResolver` for Transcription tests if the existing stubs are not sufficient.
- Regression guards the layer must preserve:
  - `Tests/SeshatTranscriptionTests/ModelDownloadProgressTests.swift:6-101`
  - `Tests/SeshatTranscriptionTests/ModelDownloadFailureTests.swift:6-54`
  - `Tests/SeshatTranscriptionTests/PrepareIdempotenceTests.swift:6-39`
  - `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift:7-49`
  - `Tests/SeshatSessionTests/SessionCoordinatorHappyPathTests.swift:7-47`
  - `Tests/SeshatSessionTests/SessionCoordinatorErrorTests.swift:50-97`
  - `Tests/SeshatAppKitTests/Components/ModeCardTests.swift:35-90`
  - `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-35`
- Manual verification updates required before calling the UI shipped:
  - Append a model-switch checklist to `Tests/SeshatAppKitTests/ManualSettingsVerification.md`.
  - Append a current-model-indicator checklist to `Tests/SeshatAppKitTests/ManualStatusItemVerification.md`.
  - Rewrite `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md` so it covers switching away from the default descriptor and verifying the correct on-disk model directory and runtime path.

## Open design questions (surface - do not resolve)
- [QUESTION] When the user selects a voice model that is not downloaded yet, does `setActive` auto-download immediately with progress surfaced through the pill/menu bar, or does it fail fast and require an explicit download action?
- [QUESTION] The prompt names `parakeet-tdt-0.6b-v3-coreml` as the new default candidate but does not pin a revision SHA or exact artifact list. What exact repository + revision should Layer 6 hardcode before implementation starts?
- [QUESTION] Current code has no first-class AI model registry, only `ModeDescriptor.aiModelID: String?` at `Sources/SeshatCore/ModeDescriptor.swift:7`. Is `ActiveModelDescriptor.aiModelID: String?` the approved Layer 6 boundary, or does main session want a new `AIModelDescriptor` namespace in this layer too?
- [QUESTION] For the menu bar, should the current-model indicator be a second disabled header row under the current mode, or should mode + model collapse into one combined header string? `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-35` currently assume one header row.

## Validation checklist (implementer ticks box-by-box)
### Step 1.1
- [ ] `Sources/SeshatCore/Models/Selection/ActiveModelDescriptor.swift:1` and `Sources/SeshatCore/Models/Selection/ModelDescriptor+Codable.swift:1` satisfy `Proposed API / contracts > Types` by making `ActiveModelDescriptor` the shared UI/storage shape instead of the split fields currently at `Sources/SeshatCore/ModeDescriptor.swift:6-8`.
- [ ] `Sources/SeshatCore/Models/Selection/BuiltInModelCatalog.swift:1` satisfies `Migration of existing call sites > Stage 1.1` by defining the v2, 110m, and v3 catalog entries without modifying `Sources/SeshatCore/ModelRegistry.swift:25-52`.

### Step 1.2
- [ ] `Sources/SeshatSession/Models/Selection/DefaultModelService.swift:1` satisfies `Proposed live implementation` by being `@MainActor`, observable, and the only owner of persisted active selection.
- [ ] `Sources/SeshatTranscription/Models/Selection/FluidAudioRuntimeVariant.swift:1` plus the new model-aware transcriber files satisfy `Migration of existing call sites > Stage 1.2` by removing the need for the hardcoded `.v2` path currently at `Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27`.

### Step 1.3
- [ ] The new Stage 1 tests under `Tests/SeshatCoreTests/Models/Selection/:1`, `Tests/SeshatSessionTests/Models/Selection/:1`, and `Tests/SeshatTranscriptionTests/Models/Selection/:1` cover the contracts listed under `Test strategy`, and every logic/state-machine change followed rigid TDD.

### Step 2.1
- [ ] `Sources/SeshatSession/SessionCoordinator.swift:28-38`, `Sources/SeshatSession/SessionCoordinator.swift:103-113`, and `Sources/SeshatAppKit/Composition/AppComposition.swift:10-25` now satisfy `Migration of existing call sites > Stage 2.1`: no process-wide fixed `FluidAudioTranscriber()` remains, and the coordinator resolves the active voice model per recording session.
- [ ] `Tests/SeshatSessionTests/SessionCoordinatorPreparationTests.swift:7-49` and the new model-selection session test still prove the stop/prepare race is safe after the swap.

### Step 2.2
- [ ] `Sources/SeshatAppKit/Settings/ModesTab.swift:25-42` and `Sources/SeshatAppKit/Components/ModeCard.swift:15-46` satisfy `Migration of existing call sites > Stage 2.2`: no direct `ModelRegistry.descriptor(for:)`, raw `mode.aiModelID ?? "No AI"`, or loose `voiceModel` / `aiModelPreset` path remains.
- [ ] If `Sources/SeshatAppKit/Settings/AIModelsTab.swift:5-45` still exists, it now satisfies `Migration of existing call sites > Stage 2.2` by reading `ModelService.activeDescriptor` rather than `ModelRegistry.defaultModelId`.

### Step 2.3
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-27`, `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:65-135`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:193-202` satisfy `Migration of existing call sites > Stage 2.3` by rendering a current-model indicator from `ModelService`.
- [ ] `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-35` still pass after the header contract is updated per the chosen menu-bar design.

### Step 2.4
- [ ] `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:122-124` satisfies `Migration of existing call sites > Stage 2.4`: no hardcoded `Parakeet TDT 0.6B` copy remains.
- [ ] Any landed Modes CRUD files matching the design at `plans/App UI design/Seshat Q4_Q5 Handoff Spec.md:50-58` satisfy `Migration of existing call sites > Stage 2.4` by sourcing their pickers from `ModelService.registeredModels` and persisting `ActiveModelDescriptor`.

### Step 3.1
- [ ] `Sources/SeshatCore/Config.swift:7-10`, `Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27`, `Sources/SeshatTranscription/FluidAudioTranscriber.swift:23-52`, and `Sources/SeshatAppKit/Composition/AppComposition.swift:15-24` no longer contain the legacy fixed-default path listed in `Migration of existing call sites > Stage 3.1`.

### Step 3.2
- [ ] `Sources/SeshatCore/ModeDescriptor.swift:29`, `Sources/SeshatAppKit/Settings/ModesTab.swift:27-42`, `Sources/SeshatAppKit/Components/ModeCard.swift:16-18`, and any surviving `Sources/SeshatAppKit/Settings/AIModelsTab.swift:5-45` no longer use direct registry lookups or the loose two-string UI path described in `Migration of existing call sites > Stage 3.2`.
- [ ] No `SeshatActiveModelDescriptor` symbol was present before deletion work began; the hand-off report explicitly records that absence instead of claiming a deleted type that never existed.

### Step 3.3
- [ ] `Tests/SeshatCoreTests/ModelRegistryTests.swift:4-24`, `Tests/SeshatCoreTests/ModeDescriptorTests.swift:4-17`, `Tests/SeshatTranscriptionTests/FluidAudioTranscriberCompileTests.swift:5-43`, `Tests/SeshatTranscriptionTests/ManualTranscriptionVerification.md:3-25`, `Tests/SeshatAppKitTests/ManualSettingsVerification.md:3-23`, and `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:1-26` have been rewritten or deleted so they no longer encode a v2-only default world.

### Global
- [ ] No files outside "Observed current spread" modified (unless in the explicit Stage 1 collision list under `Proposed live implementation`).
- [ ] No `Color(hex:` outside `Theme/*` (house rule).
- [ ] No direct `UserDefaults.standard.*` - typed resolvers only.
- [ ] No `type` / `kind` / `intent` column added to SQLite.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests named in plan pass.

## Backlog tickets authored
- `plans/backlog/model-switch-download-ux.md` - author only if main session defers the auto-download vs explicit-download decision.
- `plans/backlog/ai-model-registry.md` - author only if Layer 6 ships with string-backed `aiModelID` and defers a first-class AI model registry.

## Inter-layer dependencies
- **Requires**: Layer 2 Stage 1 and Stage 2 (the service must use the managed `models/` directory through the storage layer, not `SeshatConfig` directly).
- **Requires**: Layer 3 Stage 1 and Stage 2 (persist the active descriptor through `Preference<ActiveModelDescriptor>` instead of raw `UserDefaults` access).
- **Blocks**: Layer 7 (pipeline selection eventually keys off the same active-mode/model source of truth).
- **Blocks**: Phase 2 / Manus Modes UI work that needs a canonical voice-model picker and current-model indicator.

## Commit style
`trunk: layer 6.N: <verb-led subject>`. Test + fix in same commit.
