# #089 — Modes editor: IMPLEMENTATION

Single-commit close-out plan (L-30, L-31). Build sequence ordered to compile cleanly only at the END (single commit, single compile). Use `swift build` as a sanity check during impl; do not run `swift test` between stages. Full suite runs once before the single commit.

**Path verification**: every `Sources/`/`Tests/` citation grep-verified at write-time per `feedback_pre_spin_grep.md`.

## Build sequence

Nine stages (A through I). Many intermediate states won't compile (intentional — the schema migration is atomic). Implementer goes straight through, then compiles + tests at close.

### Stage A — Foundation (Core types)

**A.1** — `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift`
Add two new `SettingKey<Bool>`s. Constructor signature is `SettingKey(key:default:)` (codex DESIGN-review-2 verified):
```swift
public static let vadAutoStopEnabled = SettingKey<Bool>(
    key: VadAutoStopEnabledPreference.userDefaultsKey,
    default: VadAutoStopEnabledPreference.defaultValue
)
public static let autoPasteEnabled = SettingKey<Bool>(
    key: AutoPasteEnabledPreference.userDefaultsKey,
    default: AutoPasteEnabledPreference.defaultValue
)
```

**A.2** — `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift`
Add two fields to the struct:
- `public var glyph: String` (init param defaults `"mic"` for missing-key Codable decode).
- `public var hotkey: HotkeyPreference?` (decode missing-key as nil).

Update memberwise init + `CodingKeys`. Decode-side: `decodeIfPresent` with the defaults above.

**A.3** — `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift`
Rename field `activeModeID` → `defaultModeID`. Update `CodingKeys`, init param, decode/encode, doc comment (lines 13-27). No migration code — pre-dogfood (L-31). Existing dev-local doc fails to decode → fresh empty document.

**A.4** — `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift`
Add leading `enabled: Parameter<Bool>` to `.vad`:
```swift
case vad(
    enabled: Parameter<Bool>,                        // NEW
    silenceThreshold: Parameter<TimeInterval>,
    showWarning: Parameter<Bool>,
    showAutoStoppedNotification: Parameter<Bool>
)
```
Codable: `decodeIfPresent` for `enabled`; default `.setting(PreferenceKeys.vadAutoStopEnabled)` on missing.

**A.5** — `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift`
Add `enabled` parameter to `.frontmostPaste`:
```swift
case frontmostPaste(enabled: Parameter<Bool>)        // was: case frontmostPaste
```
Codable: `decodeIfPresent` for `enabled`; default `.setting(PreferenceKeys.autoPasteEnabled)` on missing. `.clipboard(restoreEnabled:)` shape unchanged.

**A.6** — `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift` (literal)
Update `WorkflowMode.dictation` literal to declare the new parameters and built-in `.vad`:
```swift
public static let dictation = WorkflowMode(
    id: "dictation", name: "Dictation", glyph: "mic", hotkey: nil,
    pipelineShape: .batch,
    processors: [.transcriber(kind: .asr)],
    captureControllers: [
        .manualHotkey,
        .vad(
            enabled: .setting(PreferenceKeys.vadAutoStopEnabled),
            silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
            showWarning: .setting(PreferenceKeys.vadShowStoppingWarning),
            showAutoStoppedNotification: .setting(PreferenceKeys.vadShowAutoStoppedNotification)
        )
    ],
    outputSinks: [
        .clipboard(restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)),
        .frontmostPaste(enabled: .setting(PreferenceKeys.autoPasteEnabled)),
        .transcriptHistorySQLite
    ]
)
```

**A.7** — `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift`
Update bound enum cases:
```swift
public enum BoundCaptureController: Sendable, Equatable {
    case vad(
        enabled: Bool,                               // NEW
        silenceThreshold: TimeInterval,
        showWarning: Bool,
        showAutoStoppedNotification: Bool
    )
    case manualHotkey
}

public enum BoundOutputSink: Sendable, Equatable {
    case clipboard(restoreEnabled: Bool)
    case frontmostPaste(enabled: Bool)               // was: case frontmostPaste
    case transcriptHistorySQLite
}
```

### Stage B — Domain layer (Core + AppKit + Session callsites)

**B.1** — `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift`

Replace `var activeMode: WorkflowMode` with two state surfaces; both reads under existing `lock.withLock` per L-7:

```swift
private var inMemoryCurrentID: String?     // NEW — runtime-only

public var defaultMode: WorkflowMode {
    lock.withLock { resolveDefaultLocked() }
}
public var currentMode: WorkflowMode {
    lock.withLock { resolveCurrentLocked() }
}

public func setDefault(id: String) throws {
    try lock.withLock {
        guard let mode = resolveModeLocked(id: id) else {
            throw WorkflowModeRegistryError.unknownMode(id)
        }
        try WorkflowModeValidator.validate(mode, availableKinds: availableKindsProvider())
        document.defaultModeID = id
        try store.save(document)
    }
    broadcastDefaultMode()    // renamed from broadcastActiveMode
}

public func setCurrent(id: String) {
    lock.withLock {
        if resolveModeLocked(id: id) != nil {
            inMemoryCurrentID = id
        }   // unknown id = no-op (silent fallback)
    }
    broadcastCurrentMode()    // NEW
}

public func reorderCustom(from: Int, to: Int) throws {
    try lock.withLock {
        guard from >= 0, from < document.customModes.count,
              to >= 0, to < document.customModes.count else {
            throw WorkflowModeRegistryError.invalidIndex
        }
        let moved = document.customModes.remove(at: from)
        document.customModes.insert(moved, at: to)
        try store.save(document)
    }
    broadcastCustomModes()    // NEW
}

public func nextAvailableName(_ basename: String) -> String {
    lock.withLock {
        let pattern = #"^\#(NSRegularExpression.escapedPattern(for: basename))( (\d+))?$"#
        let regex = try? NSRegularExpression(pattern: pattern)
        var maxSuffix: Int? = nil
        var basenameTaken = false
        for mode in document.customModes {
            // ... match name against regex, track max suffix and whether bare basename is taken
        }
        if !basenameTaken { return basename }
        return "\(basename) \((maxSuffix ?? 1) + 1)"
    }
}

public func deleteCustom(id: String) throws {
    try lock.withLock {
        document.customModes.removeAll { $0.id == id }
        if document.defaultModeID == id { document.defaultModeID = nil }
        if inMemoryCurrentID == id { inMemoryCurrentID = nil }
        try store.save(document)
    }
    broadcastDefaultMode()
    broadcastCurrentMode()
    broadcastCustomModes()
}

public func saveCustom(_ mode: WorkflowMode) throws {
    // ... existing validation + dedupe logic stays ...
    try lock.withLock {
        // ... insert or replace in customModes; persist ...
    }
    broadcastCustomModes()                              // NEW (codex IMPL-review-1 drift §F.5/F.7)
    if document.defaultModeID == mode.id { broadcastDefaultMode() }
    if inMemoryCurrentID == mode.id { broadcastCurrentMode() }
}
```

**Stale-ID auto-clear at init** (codex IMPL-review-1 drift §H.1): in `init`, after loading the document, validate `defaultModeID` against `customModes`. If stale (id present but no matching mode), clear the field and persist. Walk:

```swift
public init(...) {
    // ...load document...
    if let id = document.defaultModeID,
       !document.customModes.contains(where: { $0.id == id }) {
        document.defaultModeID = nil
        try? store.save(document)   // soft-fail; init shouldn't throw on save
    }
    // ...rest of init...
}
```

**Delete** `mutateActiveOrFork(...)`. **Delete** `setActive(id:)`. Replace internal `resolveActiveLocked` with `resolveDefaultLocked` (resolves `defaultModeID` → mode or `.dictation`) + `resolveCurrentLocked` (resolves `inMemoryCurrentID` → mode, falls back to `resolveDefaultLocked`).

Add streams: `currentModeStream() -> AsyncStream<WorkflowMode>` (was `activeModeStream`) + `defaultModeStream()` + `customModesStream()`.

**B.2** — Update all `activeMode` / `activeModeID` / `activeModeStream` / `setActive(id:)` callsites. Compile-blocking for AppStore + SessionCoordinator + multiple tests + AppMain.

| File | Change |
|---|---|
| `Sources/PersonalScribeSession/SessionCoordinator.swift:386` | `registry.activeMode` → `registry.currentMode` |
| `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineContextSnapshot.swift:4-15` | Field name unchanged; source becomes `currentMode` (caller passes it) |
| `Sources/PersonalScribeSession/Pipeline/PostProcessing/PostProcessingContext.swift:5-20` | Same: field unchanged, source updated |
| `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:543` | DTO passthrough |
| `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:203,272,277,394` | Reads `snapshot.activeMode` — **DTO field stable, no change** |
| `Sources/PersonalScribeAppKit/MenuBar/StatusItemMenuModel.swift:153,198,199` | Label-only `activeModeName` arg — stays |
| `Sources/PersonalScribeCore/AppStore/AppStoreSnapshot.swift:6,14,21` | DTO field stable; source becomes `currentMode` |
| `Sources/PersonalScribeCore/AppStore/AppStore.swift:17,63,104,106,170,172,256` | **6 hits** — flip `registry.activeMode` → `registry.currentMode` and `activeModeStream()` → `currentModeStream()`. Update `handleActiveModeChange` → `handleCurrentModeChange` |
| `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:204,271` | **`setActive(id:)` callers** (codex IMPL-review-1 §3) — both → `setCurrent(id:)`. These are menu-bar / pill-switcher mode switches; user picking a mode mid-session is a "current" change, not a "default" change |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift:13-27` | Doc comment rewrite |
| `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift:14-34,30,44,72,128,140,165` | Update fixtures + assertions. `activeModeID` → `defaultModeID`; `setActive` → `setDefault` (where setting the persisted value) OR `setCurrent` (where setting runtime); rewrite `testSetActiveValidatesAvailableKinds` → `testSetDefaultValidatesAvailableKinds`. The new H.1-H.5 tests subsume some of these. |
| `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeStoreTests.swift:104` | `setActive(id:)` → `setDefault(id:)` |
| `Tests/PersonalScribeCoreTests/AppStore/AppStoreTests.swift:132` | `setActive(id:)` → `setDefault(id:)` (the test verifies the persisted-active flow → that's now `defaultMode`) |
| `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift:49,62,117,124` | **File deleted in Stage G** — all four `setActive(id:)` callsites die with the file |

**B.3** — Delete `Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift` + drop wiring in `Sources/PersonalScribeAppKit/Composition/AppComposition.swift` (search for `LegacyToggleMigrator` references; remove). Drop the AppComposition's first-launch hook that called the migrator.

### Stage C — Pipeline + delivery (Session + AppKit)

**C.1** — `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:73-99`
`buildCaptureController` resolves the new `enabled` Parameter via `ParameterResolver.resolve(_:from:)`. Same for `buildOutputSink` for `.frontmostPaste(enabled:)`. ~8 lines added across the two builders.

**C.2** — `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:798-865`

Both `SessionPipelineOrchestrator` (line 5) and `SessionCoordinator` (line 6) are `actor`s — codex IMPL-review-1 §2 caught this. Plumbing must respect actor isolation.

Two changes:
1. VAD wiring path checks resolved `enabled` before wiring — gate on `enabled == true`.
2. **New actor-isolated accessor**: `public func currentBoundRecipe() -> BoundRecipe? { boundRecipe }` (line ~140 alongside `bindRecipeForNextSession`). The field stays `private var`; the accessor is the public seam. Lifetime spec: `boundRecipe` is set by `bindRecipeForNextSession(_:)` at session start and **persists across sessions** (current behavior). It's nil only at app launch before any session starts. `MenuBarSceneModel.deliverBatch` is invoked AFTER a session ends — so the recipe of the just-ended session is still available. Reframe: not "nil between sessions"; rather "nil only before the first-ever session." The early-return guard in C.6 handles the launch-edge case.

**C.3** — `Sources/PersonalScribeSession/SessionCoordinator.swift` (the actor; field is `pipeline`, not `orchestrator`)

New async accessor crossing actor boundary:
```swift
public func currentBoundRecipe() async -> BoundRecipe? {
    await pipeline.currentBoundRecipe()
}
```
**`async`** is required — codex IMPL-review-1 §2: cross-actor call needs `await`.

**C.4** — `Sources/PersonalScribeCore/WorkflowMode/BoundOutputSink.swift` (NEW FILE) + `Sources/PersonalScribeCore/Output/OutputService.swift`

Codex IMPL-review-1 §1 caught: `PersonalScribeSession` already imports `PersonalScribeCore` (Package.swift:52-57,84-92), so my prior "import Session in Core" creates a cycle. **Resolution**: move `BoundOutputSink` to Core.

Steps:
1. Create new file `Sources/PersonalScribeCore/WorkflowMode/BoundOutputSink.swift` with the enum:
   ```swift
   public enum BoundOutputSink: Sendable, Equatable, Codable {
       case clipboard(restoreEnabled: Bool)
       case frontmostPaste(enabled: Bool)
       case transcriptHistorySQLite
   }
   ```
2. Remove the `BoundOutputSink` enum from `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift:60-66`. `BoundRecipe` now imports `PersonalScribeCore` (already does).
3. Update `OutputService.swift`:
   ```swift
   public protocol OutputService: AnyObject, Sendable {
       func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult
   }
   ```
4. **Update test fallout** (codex IMPL-review-1 §1): every `deliverBatch(text:)` callsite changes to `deliverBatch(text:sinks:)`. Test sites that need updating:
   - `Tests/PersonalScribeCoreTests/Output/OutputContractsTests.swift:40-61`
   - `Tests/PersonalScribeAppKitTests/Fakes/OutputServiceDoubles.swift:4-27`
   - `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:69-545` (extensive — every test passes the sinks array now)
   - Any other doubles or test that mock `deliverBatch` — grep `deliverBatch` Tests/.

**C.5** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-79`
Rewrite delivery to walk sinks:
```swift
public func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
    let clipboardSink: (restoreEnabled: Bool)? = sinks.firstNonNil {
        if case .clipboard(let restore) = $0 { return (restoreEnabled: restore) } else { return nil }
    }
    let pasteEnabled: Bool = sinks.firstNonNil {
        if case .frontmostPaste(let enabled) = $0 { return enabled } else { return nil }
    } ?? false

    if let clipboardSink {
        // existing pasteboard write logic
        if clipboardSink.restoreEnabled {
            // schedule restore using ClipboardRestoreDelay.resolve(from:) — global only
        }
    }
    if pasteEnabled {
        // existing CGEventPost(Cmd+V) path — unchanged
    }
    return /* OutputResult */
}
```
Remove the `AutoPasteEnabledPreference.resolve(from:)` and `ClipboardRestoreEnabledPreference.resolve(from:)` reads at lines 76-77. `ClipboardRestoreDelay.resolve(from:)` stays (global-only).

**C.6** — `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:142-152`
Update `deliverBatch` caller. Existing callsite is already `async` (uses `await outputService.deliverBatch(...)`) so adding another `await` is fine:
```swift
guard let recipe = await sessionCoordinator.currentBoundRecipe() else { return }
let result = await outputService.deliverBatch(text: transcript, sinks: recipe.outputSinks)
```

### Stage D — Hotkey infrastructure (AppKit)

**D.1** — `Sources/PersonalScribeAppKit/Settings/ReservedInAppHotkeys.swift:37`
Extend signature with optional param:
```swift
static func reservationReason(
    for preference: HotkeyPreference,
    additionalReservations: [HotkeyPreference] = []
) -> String?
```
Loop the additional list inside the body; return early with a descriptive reason on match (e.g. `"Used by mode \"<name>\""` — caller passes the name via `additionalReservations` shape if desired, OR keep the reason generic and the caller surfaces context separately).

**D.2** — `Sources/PersonalScribeAppKit/Settings/HotkeyRecorder.swift:11`
Public init becomes:
```swift
public init(
    currentPreference: HotkeyPreference,
    onConfirm: @escaping @MainActor (HotkeyPreference) -> Void,
    onCancel: @escaping @MainActor () -> Void,
    additionalReservations: [HotkeyPreference] = []
)
```
Pipe the additional list through to internal `reservationReason` calls. Existing call sites (Settings UI for global hotkey) compile unchanged via the default param.

**D.3** — `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:260`
Add `func updatePerModeHotkeys(_ modes: [WorkflowMode])`. Internally maintains `[HotkeyPreference: HotkeyAction]` where `HotkeyAction = .startGlobalRecording | .activateModeAndRecord(modeID: String)`. On per-mode hotkey fire: synchronously `setCurrent(id:)` on the registry, then start recording.

The monitor's existing implementation reads a mutable binding (codex confirmed live-reconfigurable, no Carbon teardown needed). Adding the per-mode dispatch table is additive.

**D.4** — `Sources/PersonalScribeAppKit/Composition/AppComposition.swift:217-228`
Wire the initial call: `hotkeyMonitor.updatePerModeHotkeys(workflowModeRegistry.allModes)` after monitor start. Subscribe to the registry's `customModesStream()` to re-call on changes.

### Stage E — GeneralTab simplification (AppKit)

**E.1** — `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:725,755,786,831`
Three setters drop `mutateActiveOrFork` calls:
- `setAutoPasteEnabled(_:)` — just `AutoPasteEnabledPreference.persist(_:to:)`. No recipe mutation.
- `setClipboardRestoreEnabled(_:)` — just persist.
- `setVadAutoStopEnabled(_:)` — just `VadAutoStopEnabledPreference.persist(_:to:)`. No recipe mutation.

The toggles' UI bindings stay; `@Published` state stays (driven by UserDefaults reads). Recipe reads via `Parameter.setting(...)` cascade pick up the new value automatically on next session start (eager-binding per L-25 from #078; no live mid-session change).

**E.2** — Delete tests for the removed coupling: `Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelRecipeBridgeTests.swift` (codex confirmed location). Keep tests for the surviving toggle behavior (UserDefaults persistence).

### Stage F — Modes editor view layer (new AppKit dir)

New directory: `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/`.

| File | Notes |
|---|---|
| **F.1** `Preset.swift` | Enum `Preset: String, CaseIterable { dictation, notes, meeting, streamingDictation }`. `displayName`, `glyph`, `subtitle`, `materialize(name:) -> WorkflowMode`. `Preset.dictation.materialize(name:)` delegates to `WorkflowMode.dictation` (replaces id + name). |
| **F.2** `ModeRecipeMutators.swift` | Pure functions on `WorkflowMode` — `withRealtime`, `withAutoStop(parameter:)`, `withAutoPaste(parameter:)`, `withRestoreClipboard(parameter:)`, `withDiarization(_:)`, `withHotkey(_:)`. Each returns a new mode with the relevant pieces rebuilt (e.g. `withRealtime(true)` flips `pipelineShape` + swaps `.transcriber` → `.streamingTranscriber`). |
| **F.3** `ParameterPickerView.swift` | Reusable three-option picker for `Parameter<Bool>`. Three cases: "Default (Live: <value>)" / "Force On" / "Force Off". The "Default" parenthetical reads live via UserDefaults binding. |
| **F.4** `ModeRowView.swift` | HStack: glyph + name + dot (when `mode.id == currentModeID`) + star (filled when `mode.id == defaultModeID`, tap → `setDefault`). Validity warning chip when `validityByID[mode.id] == .invalid`. |
| **F.5** `ModesListViewModel.swift` | `@MainActor`, `ObservableObject`. `@Published` raw view state (`customModes`, `defaultModeID`, `currentModeID`, `validityByID`). Subscribes to `WorkflowModeRegistry` streams + `ActiveModelService.downloadStates`. Methods: `setDefault`, `delete`, `reorder`, `create(preset:)`. |
| **F.6** `ModesListView.swift` | `NavigationStack` host. Empty-state OR `List` with `.onMove(perform: viewModel.reorder)`. `+` opens `PresetPickerPopover`. |
| **F.7** `ModeDetailViewModel.swift` | `@MainActor`. Owns the mode being edited. Setters rebuild recipe via `ModeRecipeMutators` and call `registry.saveCustom(_:)` autosave. Validation via `WorkflowModeValidator`. |
| **F.8** `ModeDetailView.swift` | Push-nav target. Cards in L-18 order: Pipeline (Realtime toggle), Voice Model (read-only), Optional Processors (Diarization toggle), Capture (Auto-stop ParameterPicker), Output (Auto-paste + Restore-clipboard ParameterPickers), Hotkey (recorder card), Delete. |
| **F.9** `PresetPickerPopover.swift` | Popover from `+` with 4 cards. On pick: `viewModel.create(preset:) -> WorkflowMode`, push detail. |
| **F.10** `ModesTab.swift` (rewrite) | Body becomes `NavigationStack { ModesListView(viewModel:) }`. Drop the existing empty-state-when-no-asr-downloaded gate (validity surface handles it). |

### Stage G — Deletions

| File | Reason |
|---|---|
| `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTabViewModel.swift` | Superseded by `ModesListViewModel`. |
| `Sources/PersonalScribeAppKit/Components/ModeCard.swift` | Superseded by `ModeRowView`. |
| `Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift` | Done in Stage B.3. |
| `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift` | Tests for deleted VM. |
| `Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelRecipeBridgeTests.swift` | Done in Stage E.2. |
| `Tests/PersonalScribeSessionTests/WorkflowMode/LegacyToggleMigratorTests.swift` (if exists) | Migrator gone. |

### Stage H — Tests

**Seven new behavior tests + 1 existing-test rename.** Trimmed from 9 to 7 after fluff audit (per `feedback_test_rigor_no_fluff.md` memory rule). Use real components + minimal test doubles.

**Registry suite** — `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift`:

| # | Test name | Scenario | Why not fluff |
|---|---|---|---|
| H.1 | `testInitClearsStaleDefaultModeID` | Load document with `defaultModeID = "abc"` BUT `customModes` empty (or doesn't contain "abc"). Init the registry. Assert `document.defaultModeID == nil` after init AND `fakeStore.savedDocuments.last?.defaultModeID == nil` (auto-clear written through). | Load-bearing side-effect at init. The "happy path" (nil → .dictation, valid id → resolves) is covered implicitly by every other test that touches `defaultMode`; only the stale-id write-through is unique. |
| H.2 | `testCreatePresetSkipsNameGaps` | Save preset → name "Dictation". Save again → "Dictation 2". Delete "Dictation". Save another → "Dictation 3" (skip-gaps, NOT reuse). | Pins the design choice (skip-gaps over reuse). Only proof is the 3-step sequence. |
| H.3 | `testDeleteDefaultClearsDefault` | Setup: customModes contains "abc"; setDefault("abc"); setCurrent("abc"). deleteCustom("abc"). Assert `document.defaultModeID == nil`, `defaultMode == .dictation`, `currentMode == .dictation`. | Three assertions on three distinct state pieces with three distinct failure modes. Behavior change from previous code (was: set defaultModeID to dictation.id; now: clear to nil). |
| H.4 | `testReorderPersistsThroughStore` | customModes = [A, B, C]. `reorderCustom(from: 0, to: 2)`. Assert `fakeStore.savedDocuments.last?.customModes` order = [B, C, A]. | Persisted-order assertion alone catches both array-mutation bug AND missing-save bug. (Trimmed: dropped redundant in-memory dual-assert.) |

**Renamed (not new)** — Existing test at `WorkflowModeRegistryTests.swift:72` is `testSetActiveValidatesAvailableKinds`. After Stage B, rename to `testSetDefaultValidatesAvailableKinds`; same body, `setActive` → `setDefault`. **Not counted as a new test.** This subsumes the old H.3 from the prior plan.

**Cross-cutting suite** — additional tests in their respective module test dirs:

| # | Test name | Location | Scenario | Why not fluff |
|---|---|---|---|---|
| H.5 | `testVadEnabledFalseSkipsWiring` | `Tests/PersonalScribeSessionTests/Pipeline/VadOrchestratorIntegrationTests.swift` (existing file at lines 319-353 has the seam) | BoundRecipe with `.vad(enabled: false, ...)`. Run a session. Assert no VAD events fire. | Inverse of existing tests that pin enabled=true. Without this, the `enabled: false` path is untested — VAD would silently still wire. |
| H.6 | `testDeliverBatchSkipsClipboardWhenNoClipboardSink` | `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift` (new test) | sinks = `[.frontmostPaste(enabled: true), .transcriptHistorySQLite]` (no `.clipboard`). Assert `NSPasteboard.general` unchanged + no restore scheduled. | Sink-truth contract from codex DESIGN-review-2 §2. Existing tests pin always-write — need updating in C.5; this test pins the new opt-out. |
| H.7 | `testReservationReasonRejectsCollidingPerModeHotkey` | `Tests/PersonalScribeAppKitTests/Settings/ReservedInAppHotkeysTests.swift` (existing, extend) | `reservationReason(for: A, additionalReservations: [A])` non-nil; without A in list → nil. | Pins the new public API param. Without it, refactor could drop the `additionalReservations` consultation silently. Small but real. |
| H.8 | `testPerModeHotkeyFireSetsCurrentAndStartsRecording` | `Tests/PersonalScribeAppKitTests/Hotkeys/GlobalHotkeyMonitorTests.swift` (existing, extend) | Register per-mode hotkey via `updatePerModeHotkeys`. Synthesize event. Assert `registry.currentMode.id == mode.id` AND recording-start callback fired. | Multi-component integration: monitor dispatches to setCurrent THEN to recording. Both legs of the dispatch table need to fire. |

**Existing tests touched by renames** — beyond H.3-rename, the registry callsite rename in B.2 will rewrite/update:
- `WorkflowModeRegistryTests.swift:30,44,128,140,165` (existing setActive callers)
- `WorkflowModeStoreTests.swift:104`
- `AppStoreTests.swift:132`

These are mechanical renames, NOT new tests.

No view-shape tests, no constant-matches-itself, no mock theater (per L-31 + 2026-04-28 grilling).

### Stage I — Manual verification + commit

**I.1** — Manual checklist. Codex IMPL-review-1 caught path drift: runbooks live at `Tests/ManualVerifications/` (`Package.swift:115-118`), NOT `Tests/PersonalScribeAppKitTests/`. Create new file `Tests/ManualVerifications/ManualModesVerification.md`:

- `MV-MODES-1` — First launch: Modes tab is empty, "+ Create your first mode" affordance visible.
- `MV-MODES-2` — `+` opens popover with 4 preset cards. Pick Dictation → row appears, push detail. Title "Dictation". Glyph mic.
- `MV-MODES-3` — In detail, edit title → blur → return to list → row reflects new name.
- `MV-MODES-4` — Tap star on row → fills. Restart → that mode is the default at launch.
- `MV-MODES-5` — Drag rows → order persists across restart. Open menu-bar Mode submenu → reflects new order.
- `MV-MODES-6` — Streaming Dictation preset with no streaming model downloaded → orange "Realtime requires a streaming ASR model" chip. Tap star → no-op + error toast. Download streaming model → chip clears, star tappable.
- `MV-MODES-7` — Set mode A as default → menu-bar switcher to mode B → app start → current = A (resets to default per L-6).
- `MV-MODES-8` — Delete mode A which is default → confirmation alert → confirm → row gone, default = unset, app start = Dictation.
- `MV-MODES-9` — GeneralTab Auto-paste / Auto-stop / Restore-clipboard toggles still present and functional. Toggle Auto-paste off in GeneralTab → built-in Dictation fallback recipe resolves to `.frontmostPaste(enabled: false)` → no Cmd+V on next recording.
- `MV-MODES-10` — Set per-mode hotkey on a custom mode → press hotkey → mode becomes current AND recording starts. Try to record same hotkey on a second mode → recorder UI shows reservation reason, blocks confirm.
- `MV-MODES-11` — **Realtime toggle exercise**: in a custom mode, flip Realtime ON. Mode glyph stays from preset; Pipeline card now shows Streaming. Save. Activate. Record. Verify partial transcripts appear (if streaming model is downloaded) — NOT just final-on-stop. Flip Realtime OFF, record again — verify final-on-stop behavior returns.
- `MV-MODES-12` — **Diarization toggle exercise**: in a custom mode (e.g. Meeting preset), Identify Speakers is on by default. Record a 2-speaker conversation. Verify transcript shows per-speaker turns (if diarization model is downloaded). Flip the toggle off → save → activate → record → verify single-speaker transcript output.

**I.2** — Pre-commit gate (run from canonical repo path, NOT a worktree):
1. `swift build --build-tests` — green.
2. `swift test` — full suite green (~1080+ tests + 5 new from Stage H).
3. Manual checklist `MV-MODES-1` through `MV-MODES-10` exercised in DMG.
4. `git diff --stat` reviewed — no surprise files.
5. Grep verification (codex IMPL-review-1 §3 — gate must include `setActive(id:`):
   ```
   grep -rn "activeMode\|activeModeID\|activeModeStream\|setActive(id:\|mutateActiveOrFork\|LegacyToggleMigrator\|ModeCard" Sources Tests
   ```
   Survivors allowed: only the DTO field `activeMode` on `AppStoreSnapshot`/`PipelineContextSnapshot`/`PostProcessingContext` (renamed source, field stable). Anything else (especially any `setActive(id:` survivor) = missed callsite.

**I.3** — Single commit at close:
```
git add Sources/PersonalScribeCore/{WorkflowMode,Preferences,AppStore,Output}/ \
        Sources/PersonalScribeSession/{WorkflowMode,Pipeline,SessionCoordinator.swift} \
        Sources/PersonalScribeAppKit/{UnifiedWindow,Settings,MenuBar,Output,Hotkeys,Composition}/ \
        Tests/PersonalScribeSessionTests/WorkflowMode/

git rm Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTabViewModel.swift \
       Sources/PersonalScribeAppKit/Components/ModeCard.swift \
       Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift \
       Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift \
       Tests/PersonalScribeAppKitTests/Settings/GeneralTabViewModelRecipeBridgeTests.swift

git commit -m "phase-3 step #089: ship Modes editor (custom recipes, push-nav detail, autosave)"
```

Commit body should reference: CHECKLIST L-locks honored; #078 fork-on-write retired; GeneralTab simplification; multi-language picker deferred to #090; per-mode model picker deferred to #090; codex CHECKLIST-review-1 + DESIGN-review-2 issues all resolved.

## Rollback plan

Single commit ⇒ `git revert <sha>` is clean. Field rename has no migration code (no migration-direction surprise). Worst case: dev-local `workflow-modes.json` decodes empty after revert; user re-creates modes.

## Risks (cross-ref CHECKLIST §Anti-patterns)

1. **Missed `activeMode*` callsites** — gate item I.2.5 catches at pre-commit.
2. **Codable shape change for `.frontmostPaste` and `.vad`** — pre-dogfood (L-31) accepts dev-local doc reset. New decode tolerates missing fields via `decodeIfPresent` + default.
3. **`OutputService` protocol change touches a Core type referencing a Session type (`BoundOutputSink`)** — risk of circular dep. Mitigation at impl: if circular, move `BoundOutputSink` to `Core` (it's the public API contract; cleaner home).
4. **VAD enabled gate in orchestrator** — single-line check before VAD wiring. Audit with `grep -rn "case .vad("` Sources/ to confirm no other dispatch sites.
5. **Hotkey recorder reused with new param** — default `additionalReservations: []` keeps existing call sites compiling unchanged.
6. **Drag-reorder + setDefault race** — both grab `lock.withLock`; serialized by NSLock. Test H.5 verifies order. setDefault is identity-by-id, doesn't depend on array index.

## What's deliberately NOT in this plan

- Per-mode model picker (#090) and language picker (#090).
- Per-mode VAD silence threshold (deferred — global only).
- Per-mode clipboard restore delay (deferred — global only).
- LLM step in pipeline (#020/#021/#022).
- Activate-for-apps (#057).
- Persist current across launches (deferred).
- Glyph picker, inline-rename in list, three-column nav.
