# Layer 4 — AppStore

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Architecture decision

[DECISION REQUIRED] Main-session must approve the selected candidate before Stage 1 starts. Do not begin implementation on Layer 4 until that sign-off happens.

### Observed state-drift bugs in the current codebase

- `Sources/SeshatSession/SessionCoordinator.swift:186-190` and `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:118-122` document the same failure from two sides: session `.error` used to collapse the pill to hidden, so a transcription failure looked like a pill crash instead of a visible error state.
- `Sources/SeshatAppKit/Composition/AppComposition.swift:48-61`, `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:94-107`, and `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:99-117` show three different recording-entry paths. Hotkey calls `coordinator.toggle()` directly, pill tap gates through onboarding and then calls `coordinator.toggle()`, and the menu bar path may request microphone access first. The same session state is being mutated from inconsistent seams.
- `Sources/SeshatAppKit/Settings/GeneralTab.swift:168-174` explicitly snapshots menu-bar visibility once at init, while `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:193-202` rebuilds the menu from a mix of cached mic state, live Input Monitoring probes, and a separate onboarding-complete provider. That is read-side state drift by construction.
- `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:69-70` hard-codes `"Quick Memo"` as the default menu header, while `Sources/SeshatCore/ModeDescriptor.swift:26-30` defines the shipped default mode as `"Dictation"`. Active mode already has two truths.
- `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:102-108` and `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:38-44` record a recent regression where menu items became effectively stale after `defaults delete`, because onboarding state and live permission state were cached in different places.

### Candidate A — Facade / republisher

Pseudocode sketch:

```swift
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var snapshot: AppStoreSnapshot

    private let session: any AppStoreSessionProviding
    private let permissions: any PermissionService
    private let activeModeSource: any AppStoreActiveModeProviding
    private let visibilityModeSource: any AppStoreVisibilityModeProviding
    private let clock: any AppStoreClock

    func start()
}

struct AppStoreSnapshot {
    var sessionState: SessionState
    var permissions: [Permission: PermissionStatus]
    var activeMode: ModeDescriptor?
    var modelDownloadProgress: ModelDownloadProgress?
    var pillVisibility: PillVisibilityState
    var lastTranscriptionResult: TranscriptionResult?
    var currentRecordingDuration: Duration?
}
```

Code-structure sketch:

- `Sources/SeshatCore/AppStore/AppStoreSnapshot.swift`
- `Sources/SeshatCore/AppStore/PillVisibilityState.swift`
- `Sources/SeshatCore/AppStore/AppStore.swift`
- `Sources/SeshatCore/AppStore/AppStoreSessionProviding.swift`
- `Sources/SeshatCore/AppStore/AppStoreActiveModeProviding.swift`
- `Sources/SeshatCore/AppStore/AppStoreVisibilityModeProviding.swift`
- Stage 2 adapter files only: `Sources/SeshatSession/AppStore/SessionCoordinator+AppStore.swift` and `Sources/SeshatAppKit/AppStore/*.swift`

Pros in Seshat's current context:

- Fits the existing target graph in `Package.swift:47-97`: `SeshatCore` can own the store contracts while `SeshatSession` and `SeshatAppKit` add adapter conformances later, with no cycle.
- Solves the current problem directly: stale reads and duplicated subscription logic across roughly three Stage 2 consumers.
- Keeps `SessionCoordinator` and Layer 1 `PermissionService` as the real state machines, which matches the prompt's scope-out rule that Layer 4 does not own session logic or permission-request logic.
- Plays well with `@MainActor` AppKit services plus actor-backed session code: the store only bridges `AsyncStream` and published snapshots onto one observable object.
- Keeps migration mechanical. Existing command flows can survive Stage 2 while reads move to one snapshot.

Cons in Seshat's current context:

- Write paths stay imperative. The hotkey, pill, and menu bar do not become one typed action pipeline in this layer.
- Some discipline still relies on reviewers: a future consumer could bypass the store and subscribe to `SessionCoordinator` directly unless the plan's deletion pass is enforced.
- To make `pillVisibility` store-owned without pulling AppKit into core, Layer 4 must introduce a new target-neutral `PillVisibilityState` enum and a small visibility-preference protocol.

Answer to the prompt's open question:

- In Candidate A, the store should own derived `pillVisibility`, but as a new core enum (`PillVisibilityState`), not as `PillOverlayViewModel.Visibility`. That is the cleanest way to eliminate the exact bug described in `PillOverlayViewModel.swift:118-122` while keeping `SeshatCore` free of AppKit imports.

### Candidate B — Redux/TCA-lite reducer

Pseudocode sketch:

```swift
@MainActor
final class AppStore: ObservableObject {
    @Published private(set) var state: AppStoreState
    private let environment: AppStoreEnvironment

    func dispatch(_ action: AppStoreAction)
}

struct AppStoreState {
    var sessionState: SessionState
    var permissions: [Permission: PermissionStatus]
    var activeMode: ModeDescriptor?
    var modelDownloadProgress: ModelDownloadProgress?
    var pillVisibility: PillVisibilityState
    var lastTranscriptionResult: TranscriptionResult?
    var currentRecordingDuration: Duration?
}

enum AppStoreAction {
    case sessionStateChanged(SessionState)
    case permissionsChanged([Permission: PermissionStatus])
    case activeModeChanged(ModeDescriptor?)
    case modelDownloadProgressChanged(ModelDownloadProgress?)
    case visibilityModeChanged(AppStoreVisibilityMode)
    case recordingDurationTicked(Duration?)
    case transcriptionResultLoaded(TranscriptionResult?)
    case recordIntent(RecordingIntentSource)
}
```

Code-structure sketch:

- `Sources/SeshatCore/AppStore/AppStoreState.swift`
- `Sources/SeshatCore/AppStore/AppStoreAction.swift`
- `Sources/SeshatCore/AppStore/AppStoreReducer.swift`
- `Sources/SeshatCore/AppStore/AppStoreEnvironment.swift`
- `Sources/SeshatCore/AppStore/AppStore.swift`
- Stage 2 effect adapters in `Sources/SeshatSession/AppStore/` and `Sources/SeshatAppKit/AppStore/`

Pros in Seshat's current context:

- Strongest guarantee that all reads and writes pass through one typed pipe.
- Reducer tests can exhaustively cover action-to-state transitions, including the `.done` and `.error` pill timing logic.
- Gives a built-in future seam if the app later grows more cross-surface workflows than the current three consumers.

Cons in Seshat's current context:

- The target graph makes this much more expensive than it looks. `SeshatCore` cannot import `SessionCoordinator`, `PillVisibilityMode`, or AppKit onboarding types, so Layer 4 would need a non-trivial effect environment before any consumer swap starts.
- It reopens command semantics for every entry point instead of just fixing the proven duplicated-read problem. That is a large refactor for a codebase that currently has only about three real read consumers.
- The concurrency story is worse: reducer dispatch would still hop to actor-backed session work and `@MainActor` permission work, so the "single mutation lane" is partially illusory unless the effect system becomes much larger than the prompt allows.
- Higher regression risk: menu bar, pill overlay, hotkey, onboarding gating, and settings preference changes all become part of the same migration at once.

Answer to the prompt's open question:

- In Candidate B, the store would also need to own derived `pillVisibility` as a core `PillVisibilityState`; otherwise the reducer still leaves one of the key state-drift bugs outside the reducer tree.

### Side-by-side comparison

| Row | Candidate A — Facade / republisher | Candidate B — Redux/TCA-lite reducer |
|---|---|---|
| Lines of new code | Medium: roughly 350-550 LoC across core store, visibility derivation, adapters, and tests | High: roughly 700-1,000 LoC once actions, reducer, effect plumbing, adapters, and tests are included |
| Subsystems touched | Core store, session adapter, visibility-mode adapter, three consumers | All of Candidate A plus every write path and effect boundary |
| Migration count | Three required consumer swaps plus composition wiring | Three consumer swaps plus a write-path rewrite for hotkey, pill, and menu commands |
| Test strategy | Focused store tests plus preserved existing regression suites | New reducer suite plus the same existing regression suites |
| Debuggability | Easy snapshot inspection in LLDB; fewer moving parts | Better theoretical action tracing, but only after extra instrumentation is built |
| Type-safety | Strong on read-side state, moderate on write-side commands | Strongest overall, but only if every effect boundary is modeled correctly |
| Swift-concurrency ergonomics | Natural fit for `AsyncStream` and `@Published` bridging | Awkward mix of reducer dispatch, actor hops, and `@MainActor` effects |
| Learning curve | Low; aligns with the current codebase style | Medium-high; introduces a new local architecture pattern |
| Risk of regression | Lower; mostly read-side consolidation | Higher; read and write semantics change together |

### Codex recommendation

Recommend Candidate A. Seshat's current defect pattern is duplicated observation and stale cached projections, not a missing reducer, and the package graph makes a reducer rewrite materially more invasive than the benefit justifies for roughly three real consumers.

### Main-session decision gate

[DECISION REQUIRED] Approve Candidate A, including the decision that Layer 4 owns a core `PillVisibilityState`, before any implementer starts Step 1.1.

## Critical discipline

> **Do NOT diverge from this plan. Silent divergence is the cardinal sin. To deviate, surface the proposed divergence in a commit-message comment AND in the hand-off report; wait for main-session confirmation. Paraphrasing the contract is divergence. Renaming a protocol the plan specifies is divergence. Choosing a different storage format than the plan specifies is divergence.**

## Why this layer exists

Layer 4 centralizes the app's read-side state model. Today the same facts are observed, cached, or re-derived in `SessionCoordinator`, `MenuBarSceneModel`, `PillOverlayViewModel`, `StatusItemController`, settings view models, and onboarding gates. That duplication is already producing real regressions: the pill's error visibility had to be patched locally, menu-bar state has stale snapshots, and active mode text is duplicated.

This refactor should not turn Layer 4 into a second session state machine. The store exists to collect the already-authoritative subsystem outputs into one observable snapshot, make the derived pill state deterministic, and let Stage 2 consumers stop subscribing to their own partial truths.

## Observed current spread

| File | Line(s) | What lives there |
|---|---|---|
| `Package.swift` | `47-97` | Target graph: `SeshatCore` cannot import `SeshatSession` or `SeshatAppKit`, so Layer 4 must be dependency-inverted. |
| `Sources/SeshatSession/SessionCoordinator.swift` | `13-17`, `54-113`, `138-217` | Session state, last result, model download progress, and the underlying recording/transcription transitions. |
| `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift` | `8-27`, `56-117`, `135-144` | Duplicated published session state, microphone permission cache, last transcript text, progress observation, and auto-paste trigger. |
| `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift` | `41-75`, `82-254` | Pill visibility state machine, `.done` and `.error` timers, and cached derivation inputs. |
| `Sources/SeshatAppKit/Overlay/PillOverlayController.swift` | `81-112` | Publisher wiring from session state and preparation progress into the pill view model. |
| `Sources/SeshatAppKit/MenuBar/StatusItemController.swift` | `31-41`, `74-92`, `193-229` | Menu-bar icon state, mixed permission sources, and NSMenu rebuild logic. |
| `Sources/SeshatAppKit/Settings/GeneralTab.swift` | `150-197` | User-facing pill-visibility and menu-bar-visibility settings, including the snapshot-at-init visibility warning. |
| `Sources/SeshatAppKit/Onboarding/OnboardingWindowController.swift` | `98-126` | Independent critical-permission gate used by pill interaction and onboarding fallback. |
| `Sources/SeshatAppKit/Composition/AppComposition.swift` | `48-61` | Hotkey path directly mutates `SessionCoordinator`. |
| `Sources/SeshatAppKit/Composition/SeshatAppMain.swift` | `75-107` | Creates separate scene/pill/status-item state flows and wires pill taps directly to `coordinator.toggle()`. |
| `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift` | `65-136` | Menu header, permission warnings, and record item copy; currently owns a hard-coded active-mode fallback. |
| `Sources/SeshatCore/ModeDescriptor.swift` | `25-38` | Real mode registry and shipped default mode descriptor. |

## Proposed API / contracts

### Types (enums, structs)

- `AppStoreSnapshot`
  Fields:
  `sessionState: SessionState`
  `permissions: [Permission: PermissionStatus]`
  `activeMode: ModeDescriptor?`
  `modelDownloadProgress: ModelDownloadProgress?`
  `pillVisibility: PillVisibilityState`
  `lastTranscriptionResult: TranscriptionResult?`
  `currentRecordingDuration: Duration?`
- `PillVisibilityState`
  Cases:
  `.hidden`
  `.idle`
  `.downloading(fractionCompleted: Double)`
  `.loading`
  `.recording`
  `.transcribing`
  `.done`
  `.error(message: String)`
- `AppStoreVisibilityMode`
  Target-neutral mirror of the three existing pill visibility preferences: `.alwaysOn`, `.autoShow`, `.hidden`. This keeps the store core-only even before Layer 3 finishes centralizing preferences.

### Protocols

- `AppStoreSessionProviding: Sendable`
  Methods:
  `stateStream() -> AsyncStream<SessionState>`
  `modelDownloadProgress() -> AsyncStream<ModelDownloadProgress>`
  `lastResult() -> TranscriptionResult?`
- `AppStoreActiveModeProviding: Sendable`
  Methods:
  `currentActiveMode() -> ModeDescriptor?`
  `activeModeStream() -> AsyncStream<ModeDescriptor?>`
- `AppStoreVisibilityModeProviding: Sendable`
  Methods:
  `currentVisibilityMode() -> AppStoreVisibilityMode`
  `visibilityModeStream() -> AsyncStream<AppStoreVisibilityMode>`
- `AppStoreClock: Sendable`
  Responsibility:
  Provide the wall-clock "now" value and a sleep/tick primitive so `currentRecordingDuration` is testable without real time.

### Errors

- None. Layer 4 republishes subsystem state; it does not define a new error domain.

## Proposed live implementation

`AppStore` should be a `@MainActor final class` in `Sources/SeshatCore/AppStore/AppStore.swift`, conforming to `ObservableObject` and publishing a single `snapshot`. That makes each consumer read one coherent value instead of recombining multiple `@Published` fields or `AsyncStream`s on its own.

The store should start four long-lived observation tasks when `start()` is called: session state, model download progress, permission snapshots, and active mode / visibility-mode changes. `lastTranscriptionResult` should refresh only when the session transitions back to `.idle`, preserving the current `MenuBarSceneModel` behavior in `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:66-77`. `currentRecordingDuration` should be derived by a store-owned clock task that starts on `.recording`, clears on `.idle`, `.transcribing`, or `.error`, and ticks at a coarse UI cadence such as 250 ms.

`pillVisibility` should move out of `PillOverlayViewModel` and into the store as a pure derived value plus two short timer-driven transitions: `.done` after `transcribing -> idle`, and `.error(message:)` after `.error`. The logic should be lifted from `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:96-149`, but rewritten against target-neutral types in `SeshatCore/AppStore/`. `PillOverlayViewModel` then becomes a thin presentation adapter instead of a second state machine.

Because `SeshatCore` cannot import `SeshatSession` or `SeshatAppKit`, Stage 1 must stop at protocols and the core store. Real adapters land in Stage 2 under new directories, not by editing existing core session files. `SessionCoordinator` should gain conformance to `AppStoreSessionProviding` from a new `Sources/SeshatSession/AppStore/SessionCoordinator+AppStore.swift` file. The existing AppKit pill-visibility preference and future Layer 6 active-mode service should each gain similar adapter files under `Sources/SeshatAppKit/AppStore/`.

## Migration of existing call sites

Stage 1 collision claim:

- `Sources/SeshatCore/AppStore/`
- `Tests/SeshatCoreTests/AppStore/`

Stage 2 adapter claim:

- `Sources/SeshatSession/AppStore/`
- `Sources/SeshatAppKit/AppStore/`

### Step 1.1 — Define the core AppStore contracts

| Change | Before | After |
|---|---|---|
| Store state shape | No app-wide snapshot type exists. | `AppStoreSnapshot`, `PillVisibilityState`, and `AppStoreVisibilityMode` live under `Sources/SeshatCore/AppStore/`. |
| External seams | Consumers talk to `SessionCoordinator`, settings resolvers, and permission probes directly. | `AppStoreSessionProviding`, `AppStoreActiveModeProviding`, `AppStoreVisibilityModeProviding`, and `AppStoreClock` define the only inputs Layer 4 needs. |

Parallel Stage 1 with:

- Layers 2, 3, 5, 7, 8, and 9 Stage 1 immediately.
- Layer 6 Stage 1 immediately, because `ModeDescriptor` already lives in `SeshatCore`.
- Layer 1 Stage 1 only after the exact `Permission` and `PermissionStatus` type names are settled; do not invent substitute names in Layer 4.

Depends on:

- Architecture-decision sign-off for Candidate A.

Validation checklist:

- [ ] `Sources/SeshatCore/AppStore/AppStoreSnapshot.swift:1-80` defines every required field from `plans/CENTRAL_LAYERS_PROMPT.md:243-250` and from this plan's `Proposed API / contracts -> Types`.
- [ ] `Sources/SeshatCore/AppStore/PillVisibilityState.swift:1-40` is target-neutral and imports no AppKit-only types, matching `Architecture decision -> Candidate A` and `Proposed live implementation`.
- [ ] `Sources/SeshatCore/AppStore/AppStoreVisibilityMode.swift:1-30` mirrors only the three preference cases and does not persist anything itself, matching `Architecture decision -> Candidate A` and the scope-out rule that Layer 4 does not own settings persistence.
- [ ] No files outside `Sources/SeshatCore/AppStore/` are modified in this step, matching the Stage 1 collision rule.

### Step 1.2 — Implement the live facade store

| Change | Before | After |
|---|---|---|
| Observation | Each consumer opens its own stream or cache. | `AppStore` owns one observation fan-in and publishes one coherent snapshot. |
| Derived UI state | `PillOverlayViewModel` owns error/done timers and visibility derivation. | `AppStore` owns target-neutral `pillVisibility` and recording-duration derivation. |

Parallel Stage 1 with:

- Same as Step 1.1 once that step lands.

Depends on:

- Step 1.1 complete.

Validation checklist:

- [ ] `Sources/SeshatCore/AppStore/AppStore.swift:1-220` is `@MainActor`, `ObservableObject`, and publishes a single `snapshot`, matching `Architecture decision -> Candidate A` and `Proposed live implementation` paragraph 1.
- [ ] `Sources/SeshatCore/AppStore/AppStore.swift:221-340` starts observation tasks for session state, model download progress, permissions, active mode, and visibility mode, matching `Proposed live implementation` paragraphs 2-4.
- [ ] `Sources/SeshatCore/AppStore/AppStore.swift:341-430` derives `.done`, `.error(message:)`, and `currentRecordingDuration`, replacing the logic currently spread across `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:96-149`, as required by `Architecture decision -> Observed state-drift bugs`.
- [ ] No existing consumer file is modified in this step, matching Stage 1's "build in parallel" rule.

### Step 1.3 — Add core store tests and fakes

| Change | Before | After |
|---|---|---|
| Store coverage | No Layer 4 tests exist. | New unit tests prove snapshot republishing, pill visibility derivation, last-result refresh, and recording-duration ticking. |
| Fake seams | Existing tests fake each consumer separately. | New Layer 4 fakes let future consumer swaps test against one snapshot source. |

Parallel Stage 1 with:

- Same as Step 1.2.

Depends on:

- Steps 1.1 and 1.2 complete.

Validation checklist:

- [ ] `Tests/SeshatCoreTests/AppStore/AppStoreTests.swift:1-260` covers session-state republishing, permission republishing, active-mode changes, visibility-mode changes, `.done`, `.error(message:)`, and recording-duration ticks, matching `Test strategy -> Unit tests`.
- [ ] `Tests/SeshatCoreTests/AppStore/Fakes/FakeAppStoreSessionProvider.swift:1-80`, `Tests/SeshatCoreTests/AppStore/Fakes/FakeVisibilityModeProvider.swift:1-60`, and sibling fakes exist, matching `Test strategy -> Fakes for the new protocols`.
- [ ] Existing regression suites named in `Test strategy -> Regression guards` are untouched in this step, matching the Stage 1 rule that no consumer behavior changes yet.

### Step 2.1 — Swap MenuBarSceneModel onto AppStore

| Change | Before | After |
|---|---|---|
| Read-side state | `MenuBarSceneModel` owns `state`, `permissionState`, `lastResultText`, `preparationProgress`, and opens two coordinator streams. | `MenuBarSceneModel` receives `AppStore`, projects from `snapshot`, and stops opening its own session/progress streams. |
| App composition | `SeshatAppMain` builds separate state pipes. | `SeshatAppMain` creates one shared `AppStore`, starts it, and passes it into `MenuBarSceneModel`. |

Stage 2 dependencies:

- Steps 1.1-1.3 complete.
- Layer 1 Stage 2 complete, so the store reads real `PermissionService` output instead of legacy microphone-only state.
- Layer 6 Stage 2 complete, so the store's `activeMode` field has a real provider instead of forcing a second mode fallback.

Validation checklist:

- [ ] `Sources/SeshatAppKit/Composition/SeshatAppMain.swift:36-168` creates exactly one `AppStore` for the app session, calls `start()`, and injects it into `MenuBarSceneModel`, matching `Proposed live implementation` paragraph 4 and this step's second row.
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151` no longer calls `SessionCoordinator.stateStream()` or `modelDownloadProgress()` directly; it reads store state instead, matching `Architecture decision -> Candidate A` and this step's first row.
- [ ] `Sources/SeshatSession/AppStore/SessionCoordinator+AppStore.swift:1-80` adds the protocol adapter without reopening `Sources/SeshatSession/SessionCoordinator.swift`, matching `Proposed live implementation` paragraph 4.
- [ ] `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:181-259` still proves recording publication and last-result refresh, with expectations updated to flow through `AppStore` rather than direct coordinator streams.

### Step 2.2 — Swap the pill overlay path onto AppStore

| Change | Before | After |
|---|---|---|
| Visibility derivation | `PillOverlayViewModel` derives visibility from raw session/progress inputs and owns the timers. | `PillOverlayViewModel` renders store-provided `PillVisibilityState`; derivation and timers live in `AppStore`. |
| Controller wiring | `PillOverlayController` combines two publishers and pushes into `apply(...)`. | `PillOverlayController` observes `AppStore.snapshot` directly and maps only the fields the view needs. |

Stage 2 dependencies:

- Step 2.1 complete.
- Layer 1 Stage 2 complete.

Validation checklist:

- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayController.swift:62-117` subscribes to `AppStore` instead of `CombineLatest(statePublisher, preparationProgressPublisher)`, matching this step's second row.
- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:21-140` accepts already-derived visibility state and no longer owns `computeVisibility(...)`, `lastSessionState`, `lastPreparationProgress`, or the done/error timing tasks, matching `Architecture decision -> Candidate A` and `Proposed live implementation` paragraph 3.
- [ ] `Tests/SeshatCoreTests/AppStore/AppStoreTests.swift:120-220` now carries the behavioral assertions currently anchored by `Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift:46-63` and `Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift:228-279`, preserving those regressions without weakening them.
- [ ] `Tests/SeshatAppKitTests/ManualPillOverlayVerification.md:1-120` gains a new checklist item covering store-driven `.error` and `.done` transitions before the implementation is claimed shipped, matching the UI verification rule from `AGENTS.md`.

### Step 2.3 — Swap StatusItemController onto AppStore

| Change | Before | After |
|---|---|---|
| Permission reads | `StatusItemController` mixes `sceneModel.permissionState` with a live `IOHIDPermissionProbe()` call. | `StatusItemController` reads both mic and Input Monitoring status from `AppStore.snapshot.permissions`. |
| Active mode header | `StatusItemMenuModel` defaults to `"Quick Memo"`. | Menu header comes from `snapshot.activeMode?.name`, with no hard-coded fallback string in the model builder. |

Stage 2 dependencies:

- Step 2.1 complete.
- Layer 1 Stage 2 complete.
- Layer 6 Stage 2 complete.

Validation checklist:

- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-229` removes `imPermissionProbe`, `micPermissionCancellable`, and mixed-source menu rebuilding; state now comes from `AppStore`, matching `Architecture decision -> Observed state-drift bugs` and this step's first row.
- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:65-136` takes the active mode name from the injected store snapshot and does not default to `"Quick Memo"`, resolving the drift cited in `Architecture decision -> Observed state-drift bugs`.
- [ ] `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:12-35` and `Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:101-171` still assert header correctness and permission-warning behavior after the store swap.
- [ ] `Tests/SeshatAppKitTests/ManualStatusItemVerification.md:1-80` gains a checklist item proving the menu warning rows update from the store without reopening the app, matching the AppKit manual-verification rule.

### Step 3.1 — Delete duplicate read-side observation after every consumer swap lands

| Change | Before | After |
|---|---|---|
| Menu-bar duplication | `MenuBarSceneModel` still owns observation tasks and local copies after the swap. | Those local observation tasks and duplicate published caches are deleted. |
| Pill duplication | `PillOverlayViewModel` still carries the old derivation state machine. | Only presentation-facing state remains. |

Stage 3 dependencies:

- Steps 2.1-2.3 complete and green.
- Main-session confirms no remaining consumer reads session/progress/permission state outside `AppStore`.

Validation checklist:

- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151` no longer contains `observationTask`, `preparationObservationTask`, or direct coordinator stream wiring, matching Steps 2.1 and 3.1.
- [ ] `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:60-254` no longer contains `computeVisibility(...)`, `lastSessionState`, `lastPreparationProgress`, or local done/error timers, matching Step 2.2 and this step.
- [ ] Only files listed in Steps 2.1-2.3 plus the two files named in this step are touched, matching the global delete-pass discipline.

### Step 3.2 — Delete hard-coded fallbacks and mixed permission probes

| Change | Before | After |
|---|---|---|
| Status item | Hard-coded mode fallback and permission probes remain as dead code. | Status item reads only from `AppStore`. |
| Temporary adapters | Any Stage 2 shims that only existed to preserve old publisher surfaces are removed. | Remaining Layer 4 code is the core store plus thin presentation adapters. |

Stage 3 dependencies:

- Step 3.1 complete.

Validation checklist:

- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-229` contains no `PermissionProbing` dependency after deletion, matching Step 2.3 and this step.
- [ ] `Sources/SeshatAppKit/MenuBar/StatusItemMenuModel.swift:65-136` has no hard-coded active-mode fallback string, matching Step 2.3 and `Architecture decision -> Observed state-drift bugs`.
- [ ] Any temporary Stage 2 bridge file created only to keep legacy `MenuBarSceneModel` publishers alive is deleted in this step, matching Candidate A's goal of one read-side truth.

## Test strategy

- Unit tests: add `Tests/SeshatCoreTests/AppStore/AppStoreTests.swift` covering snapshot republishing, permission refresh, active-mode changes, visibility-mode changes, `.done` and `.error(message:)` visibility transitions, and recording-duration ticking.
- Integration tests: update `Tests/SeshatAppKitTests/MenuBarFlowIntegrationTests.swift` and `Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift` so the menu-bar flow still exercises recording, transcribing, and last-result publication through the shared store.
- Fakes for the new protocols: session provider fake, active-mode provider fake, visibility-mode provider fake, manual clock fake, and a Layer 1 permission-service fake publishing `[Permission: PermissionStatus]`.
- Regression guards the layer must preserve:
`Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift:46-63` `testErrorSessionStateSurfacesAsVisibleErrorPillWithMessage`
`Tests/SeshatAppKitTests/PillOverlayViewModelTests.swift:228-279` `testTransitionSequenceIdleRecordingTranscribingIdleError` and `testTranscribingToIdleShowsDoneConfirmation`
`Tests/SeshatAppKitTests/MenuBarSceneModelTests.swift:181-259` `testStartObservingPublishesRecordingAfterCoordinatorToggle` and `testIdleTransitionRefreshesLastResultTextFromCoordinator`
`Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:28-35` `testActiveModeNameIsReflectedInHeader`
`Tests/SeshatAppKitTests/MenuBar/StatusItemMenuModelTests.swift:38-62` `testSettingsAndHistoryAlwaysEnabledRegardlessOfOnboardingState`
- Manual verification runbooks to extend before claiming shipped:
`Tests/SeshatAppKitTests/ManualPillOverlayVerification.md`
`Tests/SeshatAppKitTests/ManualStatusItemVerification.md`

## Open design questions (surface — do not resolve)

- [QUESTION] Should `currentRecordingDuration` reflect wall-clock time since `.recording` began, or the captured-audio duration accumulated by the session pipeline? The current code only computes a final buffered duration at stop in `Sources/SeshatSession/SessionCoordinator.swift:191-193`; the store needs one explicit rule.
- [QUESTION] If Layer 6 slips, should main-session hold all Layer 4 Stage 2 swaps, or allow a temporary `activeMode == ModeRegistry.descriptor(for: ModeRegistry.defaultModeID)` bridge? This plan assumes "hold Layer 4 Stage 2" to avoid reintroducing a second active-mode truth.

## Validation checklist (implementer ticks box-by-box)

- [ ] `Sources/SeshatCore/AppStore/AppStoreSnapshot.swift:1-80`, `Sources/SeshatCore/AppStore/PillVisibilityState.swift:1-40`, and `Sources/SeshatCore/AppStore/AppStore.swift:1-430` exist exactly as required by Steps 1.1-1.2 and the approved `Architecture decision`.
- [ ] `Sources/SeshatAppKit/MenuBar/MenuBarSceneModel.swift:7-151`, `Sources/SeshatAppKit/Overlay/PillOverlayViewModel.swift:21-254`, and `Sources/SeshatAppKit/MenuBar/StatusItemController.swift:29-229` no longer own independent read-side session/permission/progress state after Steps 2.1-3.2.
- [ ] No files outside the step-specific change lists or explicit collision lists were modified.
- [ ] No `Color(hex:` outside `Theme/*`.
- [ ] No direct `UserDefaults.standard.*` — typed resolvers only.
- [ ] No `type` / `kind` / `intent` column added to SQLite.
- [ ] `swift build --build-tests` green (main session).
- [ ] All acceptance tests named in this plan pass.

## Backlog tickets authored

- None.

## Inter-layer dependencies

- **Requires**: Layer 1 Stage 1 for the final `Permission` / `PermissionStatus` contract names, and Layer 1 Stage 2 before any consumer swap reads live permissions from the real service.
- **Requires**: Layer 6 Stage 2 before the store can publish a live `activeMode` without inventing a second active-mode fallback.
- **Blocks**: no later layer is hard-blocked, but this layer reduces duplicate read-side migration work for any future UI consumer that would otherwise subscribe directly to `SessionCoordinator` or permission services.

## Commit style

`trunk: layer 4.N: <verb-led subject>`. Test + fix in same commit.
