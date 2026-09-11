# #089 — Modes editor: DESIGN

References CHECKLIST.md L-locks; doesn't restate them. Pre-condition: every L1–L31 lock holds. Multi-language picker = #090. Per-mode model picker = #090.

**Path verification**: every `Sources/`/`Tests/` citation in this doc is grep-verified at write-time per the `feedback_pre_spin_grep.md` memory rule.

## Architecture sketch

Three shape changes anchor everything else:

1. **`Parameter<T>` (existing) extended to two more spots** — `OutputSinkSpec.frontmostPaste(enabled: Parameter<Bool>)` (new param) and `CaptureControllerSpec.vad(enabled: Parameter<Bool>, ...)` (new leading param). No new type. Resolver stays `ParameterResolver`. Eager-at-build per #078 L25.
2. **Registry splits state** — `WorkflowModeRegistry.activeMode` becomes two: `defaultMode` (persisted in `WorkflowModeDocument.defaultModeID`) + `currentMode` (runtime, in-memory under existing `lock.withLock`). Eager-binding (`SessionCoordinator.swift:386`) reads `currentMode`.
3. **Delivery wires through `BoundRecipe`** — `MenuBarSceneModel.deliverBatch` reads the session's frozen `BoundRecipe` and passes resolved settings to `OutputService.deliverBatch(text:settings:)`. `ClipboardBatchOutput` stops reading `AutoPasteEnabledPreference` / `ClipboardRestoreEnabledPreference` from defaults (keeps reading `ClipboardRestoreDelay` — global-only per user direction).

UI is push-nav over `customModes`. Built-in `WorkflowMode.dictation` literal stays in code as fallback, gains `.vad(enabled: .setting(.vadAutoStopEnabled), ...)` and `.frontmostPaste(enabled: .setting(.autoPasteEnabled))` so global toggles drive the fallback (L-26).

## Schema deltas

### `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift`

Add **two** new `SettingKey`s. Codex DESIGN-review-2 verified: today only `vadSilenceThreshold`, `vadShowStoppingWarning`, `vadShowAutoStoppedNotification`, `clipboardRestoreEnabled` exist. Both `vadAutoStopEnabled` and `autoPasteEnabled` are missing.

Constructor signature is `SettingKey(key:default:)` (not `rawKey:`):

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

`clipboardRestoreEnabled` already exists; reused for `.clipboard(restoreEnabled:)` (current behavior). `vadSilenceThreshold` already exists; reused for the threshold parameter.

### `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift`

Add leading `enabled: Parameter<Bool>` to `.vad`:

```swift
case vad(
    enabled: Parameter<Bool>,                        // NEW
    silenceThreshold: Parameter<TimeInterval>,        // existing
    showWarning: Parameter<Bool>,                    // existing
    showAutoStoppedNotification: Parameter<Bool>     // existing
)
```

Codable: legacy `.vad(...)` without `enabled` decodes with `enabled = .setting(PreferenceKeys.vadAutoStopEnabled)`. Encode emits the field. Pre-dogfood per L-31 — broken decode of foreign documents acceptable.

### `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift`

Add `enabled: Parameter<Bool>` to `.frontmostPaste`:

```swift
case frontmostPaste(enabled: Parameter<Bool>)         // was: case frontmostPaste
```

Codable: legacy `.frontmostPaste` (no associated value) decodes with `enabled = .setting(PreferenceKeys.autoPasteEnabled)`.

`.clipboard` shape unchanged (`restoreEnabled: Parameter<Bool>` already there).

### `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift`

Two new fields + `WorkflowMode.dictation` literal updated to declare the new parameters:

```swift
public struct WorkflowMode: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public var name: String
    public var glyph: String                // NEW (default "mic" on missing-key decode)
    public var hotkey: HotkeyPreference?    // NEW (nil = no per-mode hotkey)
    public var pipelineShape: PipelineShape
    public var processors: [ProcessorSpec]
    public var captureControllers: [CaptureControllerSpec]
    public var outputSinks: [OutputSinkSpec]
}

extension WorkflowMode {
    public static let dictation = WorkflowMode(
        id: "dictation", name: "Dictation", glyph: "mic", hotkey: nil,
        pipelineShape: .batch,
        processors: [.transcriber(kind: .asr)],
        captureControllers: [
            .manualHotkey,
            .vad(
                enabled: .setting(PreferenceKeys.vadAutoStopEnabled),
                silenceThreshold: .setting(PreferenceKeys.vadSilenceThreshold),
                showWarning: .setting(PreferenceKeys.vadShowWarning),
                showAutoStoppedNotification: .setting(PreferenceKeys.vadShowAutoStoppedNotification)
            )
        ],
        outputSinks: [
            .clipboard(restoreEnabled: .setting(PreferenceKeys.clipboardRestoreEnabled)),
            .frontmostPaste(enabled: .setting(PreferenceKeys.autoPasteEnabled)),
            .transcriptHistorySQLite
        ]
    )
}
```

### `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift`

Field rename: `activeModeID` → `defaultModeID`. CodingKeys updated. Doc comment (lines 13-27) refreshed. No migration code per L-31.

### `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift`

Bound counterparts gain the new fields:

```swift
public enum BoundCaptureController: Sendable, Equatable {
    case vad(
        enabled: Bool,                                // NEW
        silenceThreshold: TimeInterval,
        showWarning: Bool,
        showAutoStoppedNotification: Bool
    )
    case manualHotkey
}

public enum BoundOutputSink: Sendable, Equatable {
    case clipboard(restoreEnabled: Bool)              // unchanged
    case frontmostPaste(enabled: Bool)                // was: case frontmostPaste
    case transcriptHistorySQLite                      // unchanged
}
```

### `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:75-77,89-99`

Existing `buildCaptureController` / `buildOutputSink` extended to resolve the new parameters via `ParameterResolver.resolve(_:from:)`. Five-line additions; no structural change.

## Domain layer changes

### `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift`

Replace `activeMode` with `defaultMode` + `currentMode`. Both reads happen under existing `lock.withLock` (L-7 — NO @MainActor isolation):

```swift
@_spi(Internal) public final class WorkflowModeRegistry: ObservableObject {
    private let lock = NSLock()
    private var document: WorkflowModeDocument
    private var inMemoryCurrentID: String?     // NEW — runtime-only

    public var defaultMode: WorkflowMode {
        lock.withLock { resolveDefaultLocked() }
    }
    public var currentMode: WorkflowMode {
        lock.withLock { resolveCurrentLocked() }
    }

    public func setDefault(id: String) throws { /* validate; document.defaultModeID = id; persist; broadcast */ }
    public func setCurrent(id: String) {        /* lock; inMemoryCurrentID = id; broadcast */ }
    public func reorderCustom(from: Int, to: Int) throws { /* lock; mutate array; persist */ }
    public func nextAvailableName(_ basename: String) -> String { /* lock; scan; skip-gaps */ }

    public func deleteCustom(id: String) throws {
        // ...delete...
        if document.defaultModeID == id { document.defaultModeID = nil }   // CHANGED — was = dictation.id
        if inMemoryCurrentID == id { inMemoryCurrentID = nil }            // currentMode falls back to defaultMode → dictation
    }

    // DELETED: mutateActiveOrFork(...)
}

private func resolveDefaultLocked() -> WorkflowMode {
    if let id = document.defaultModeID,
       let mode = document.customModes.first(where: { $0.id == id }) { return mode }
    return .dictation
}

private func resolveCurrentLocked() -> WorkflowMode {
    if let id = inMemoryCurrentID,
       let mode = document.customModes.first(where: { $0.id == id }) { return mode }
    return resolveDefaultLocked()
}
```

Broadcast pattern unchanged from #078 — `activeModeStream()` becomes `currentModeStream()`. AppStore subscribes to that.

### Rename surface (per evidence inventory in CHECKLIST §Evidence)

10 callsites. Critical: **`Sources/PersonalScribeCore/AppStore/AppStore.swift:17,63,104-106,170-172,256`** (6 hits). All flip `registry.activeMode` → `registry.currentMode` and `activeModeStream()` → `currentModeStream()`. The DTO field `AppStoreSnapshot.activeMode` is preserved (it's a snapshot field, not a registry method) — but its source becomes `currentMode`. Same for `PipelineContextSnapshot.activeMode`, `PostProcessingContext.activeMode`.

`Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:203,272,277,394` reads `snapshot.activeMode` — unchanged (DTO field stable).

## Delivery path resolution (L-24)

Today: `ClipboardBatchOutput.deliverBatch(text:)` reads three globals from defaults (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-78`). After #089, delivery is driven by the session's `[BoundOutputSink]` — sink presence + resolved parameters together — passed through to the implementation.

### Protocol shape

```swift
// Sources/PersonalScribeCore/Output/OutputService.swift
public protocol OutputService: AnyObject, Sendable {
    func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult
}
```

The protocol takes the **full bound sink list**, not a flat boolean struct. Codex DESIGN-review-2 §2 caught the bug in the flat-struct shape: a recipe with `.frontmostPaste` but no `.clipboard` would still clipboard-write under a booleans-only API. Sink presence is part of the truth.

### Implementation (`ClipboardBatchOutput.deliverBatch`)

```swift
public func deliverBatch(text: String, sinks: [BoundOutputSink]) async -> OutputResult {
    let clipboardCfg: (restore: Bool)? = sinks.firstNonNil { sink in
        if case .clipboard(let restore) = sink { return (restore: restore) } else { return nil }
    }
    let pasteEnabled: Bool = sinks.firstNonNil { sink in
        if case .frontmostPaste(let enabled) = sink { return enabled } else { return nil }
    } ?? false

    if let clipboardCfg {
        // write to clipboard; if clipboardCfg.restore { schedule restore using ClipboardRestoreDelay.resolve() }
    }
    if pasteEnabled {
        // post Cmd+V via existing CGEventPost path
    }
    return /* ... */
}
```

`ClipboardRestoreDelay.resolve(from:)` keeps reading defaults directly — restore delay is global-only per user direction. Adapter walks sinks once; sink absence == feature off.

### Delivery seam (resolves codex DESIGN-review-2 §1 critical)

`MenuBarSceneModel` has no `sessionPipeline` handle today (codex caught this — `boundRecipe` is `private` to the orchestrator). New seam:

```swift
// Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift
// Field becomes accessible via internal accessor:
public func currentBoundRecipe() -> BoundRecipe? { boundRecipe }

// Sources/PersonalScribeSession/SessionCoordinator.swift
public func currentBoundRecipe() -> BoundRecipe? {
    orchestrator.currentBoundRecipe()
}

// Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:142-152
guard let recipe = sessionCoordinator.currentBoundRecipe() else {
    return  // no session bound — early-return without delivery (existing edge case)
}
let result = await outputService.deliverBatch(text: transcript, sinks: recipe.outputSinks)
```

Pull-based via the existing `SessionCoordinator` injection that `MenuBarSceneModel` already has. No new stream; no AppStoreSnapshot field; no new Adapter.

`SessionCoordinator.currentBoundRecipe()` is `nil` between sessions (matches the orchestrator's storage state). MenuBarSceneModel's existing nil-guard pattern handles that.

**Out-of-session deliveries** (e.g. `Sources/PersonalScribeAppKit/MenuBar/CopyLastTranscriptAction.swift`) don't go through this path. **#089 doesn't touch them.**

## Orchestrator: VAD enable check (resolves CHECKLIST critical-1)

`Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:798-805,842-865` currently checks for `.vad` *presence* in `boundRecipe.captureControllers`. After #089: also gates on `enabled`:

```swift
let vadCfg = boundRecipe.captureControllers.firstMap { spec -> BoundVadConfig? in
    guard case .vad(let enabled, let threshold, let warn, let notify) = spec else { return nil }
    return enabled ? .init(threshold: threshold, warn: warn, notify: notify) : nil
}
if let vadCfg { /* wire VAD as today */ }
```

Net change: one new `enabled` Bool gate before VAD wiring; everything else identical.

## Hotkey path (L-21..L-23)

### `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift`

Today exposes `updateRecordingHotkey(_ preference: HotkeyPreference)` for a single global hotkey (line 260). Extend with:

```swift
public func updatePerModeHotkeys(_ modes: [WorkflowMode])
// Re-registers the union of: global recording hotkey + every mode.hotkey != nil.
// Internally maintains a [HotkeyPreference: HotkeyAction] map, where
// HotkeyAction = .startGlobalRecording | .activateModeAndRecord(modeID: String).
// On fire: if .activateModeAndRecord, calls registry.setCurrent(id:) THEN starts recording.
```

`ModesListViewModel` calls `updatePerModeHotkeys(_:)` whenever `customModes` changes. `AppComposition` wires the initial call.

### Collision detection (resolves codex DESIGN-review-2 §4 major)

`ReservedInAppHotkeys.reservationReason(for:)` is currently static with no injected mode-hotkey set (codex caught the "verbatim reuse" overstatement). Extend signature with optional `additionalReservations`:

```swift
// Sources/PersonalScribeAppKit/Settings/ReservedInAppHotkeys.swift:37
static func reservationReason(
    for preference: HotkeyPreference,
    additionalReservations: [HotkeyPreference] = []
) -> String?
```

Existing call sites (Settings UI for global recording hotkey) pass nothing → behavior unchanged. New call site (Modes editor) passes the union of (a) currently-registered per-mode hotkeys EXCEPT this mode's own (so re-confirming your own binding doesn't conflict with itself) and (b) the global recording hotkey. The recorder threads this through.

### Mode detail hotkey card

`HotkeyRecorder.swift` init becomes `init(currentPreference:onConfirm:onCancel:additionalReservations:)`. AppKit-side: pass `additionalReservations` from `ModeDetailViewModel` (which has access to `WorkflowModeRegistry.allModes`). Caller code shape:

```swift
HotkeyRecorder(
    currentPreference: mode.hotkey ?? .empty,
    onConfirm: { newPreference in viewModel.setHotkey(newPreference) },
    onCancel: { /* dismiss sheet */ },
    additionalReservations: registry.customModes
        .filter { $0.id != mode.id }
        .compactMap(\.hotkey)
)
```

The card in `ModeDetailView` displays current `mode.hotkey` (or "None") + a "Set hotkey" button presenting the recorder; clear with a trash button.

## View layer

New directory: `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/`.

| File | Role |
|---|---|
| `ModesTab.swift` (rewrite) | `NavigationStack` host; routes between `ModesListView` (root) and `ModeDetailView` (path). |
| `ModesListView.swift` | Empty-state OR rows + `+` button. `.onMove` for reorder. Tap row body → push detail. Tap star → `setDefault`. |
| `ModesListViewModel.swift` | `@MainActor`, `ObservableObject`. Exposes `@Published var customModes`, `@Published var defaultModeID: String?`, `@Published var currentModeID: String?`, `@Published var validityByID: [String: ValidityStatus]`. Subscribes to `WorkflowModeRegistry` broadcast + `ActiveModelService.downloadStates`; recomputes `validityByID` in one pass per change. Methods: `setDefault`, `delete`, `reorder`, `create(preset:)`. |
| `ModeRowView.swift` | HStack: glyph + name + dot (when current) + star (filled when default, tappable). Validity warning chip when invalid. |
| `ModeDetailView.swift` | Push-nav target. Editable title. Cards (in L-18 order): Pipeline, Voice Model, Optional Processors, Capture, Output, Hotkey, Delete-this-mode. |
| `ModeDetailViewModel.swift` | `@MainActor`. Owns the mode being edited; mutations rebuild `WorkflowMode` and call `registry.saveCustom(_:)` autosave. Validation result exposed. |
| `PresetPickerPopover.swift` | Popover from `+` with 4 cards; on pick → `viewModel.create(preset:)`. |
| `Preset.swift` | Enum + factory. `Preset.dictation.materialize(name:)` delegates to `WorkflowMode.dictation` literal (replaces id + name); other 3 own their recipe shape. |
| `ParameterPickerView.swift` | Reusable three-option picker for `Parameter<Bool>` (Default / Force On / Force Off). Used in Capture (Auto-stop), Output (Auto-paste, Restore clipboard) cards. The "Default" option's parenthetical reads live from UserDefaults via the binding. |

Helpers (same dir):
- `ModeRecipeMutators.swift` — pure functions like `WorkflowMode.withRealtime(_:)`, `withAutoStop(parameter:)`, `withAutoPaste(parameter:)`, `withRestoreClipboard(parameter:)`, `withDiarization(_:)`, `withHotkey(_:)`. Each rebuilds the recipe pieces needed for that toggle.

### Files modified outside the new dir

| File | Change |
|---|---|
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift` | Add `glyph`, `hotkey` fields; update `.dictation` literal. |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift` | Rename `activeModeID` → `defaultModeID`; refresh doc comment. |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeRegistry.swift` | `defaultMode` + `currentMode` split; `setDefault`, `setCurrent`, `reorderCustom`, `nextAvailableName`. Delete `mutateActiveOrFork`. |
| `Sources/PersonalScribeCore/WorkflowMode/CaptureControllerSpec.swift` | `.vad(enabled: Parameter<Bool>, ...)`. |
| `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift` | `.frontmostPaste(enabled: Parameter<Bool>)`. |
| `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift` | Add `autoPasteEnabled` SettingKey. |
| `Sources/PersonalScribeCore/Output/OutputService.swift` | Extend protocol: `deliverBatch(text:settings:)`. New `ResolvedDeliverySettings` type. |
| `Sources/PersonalScribeCore/AppStore/AppStore.swift` | 6 hits flip `activeMode`/`activeModeStream` → `currentMode`/`currentModeStream`. |
| `Sources/PersonalScribeSession/SessionCoordinator.swift:386` | `registry.activeMode` → `registry.currentMode`. |
| `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` | Build new params via `ParameterResolver`. |
| `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift` | New params on bound types. |
| `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:798-865` | VAD enable check. |
| `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-79` | Stops reading `AutoPasteEnabledPreference` / `ClipboardRestoreEnabledPreference`; consumes `ResolvedDeliverySettings`. |
| `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift:142-152` | Reads session's frozen `BoundRecipe`; passes settings. |
| `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:725,755,786,831` | `setAutoPasteEnabled` / `setClipboardRestoreEnabled` / `setVadAutoStopEnabled` become plain UserDefaults writes (no `mutateActiveOrFork`). |
| `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:260` | Add `updatePerModeHotkeys(_:)` API. |

### Files deleted

| File | Reason |
|---|---|
| `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTabViewModel.swift` | Superseded by `ModesListViewModel`. |
| `Sources/PersonalScribeAppKit/Components/ModeCard.swift` | Superseded by `ModeRowView`. |
| `Sources/PersonalScribeSession/WorkflowMode/LegacyToggleMigrator.swift` | No first-launch migration needed; legacy bool prefs preserved as `.setting(...)` source. |
| `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift` | Tests for deleted VM. |

## Preset shapes

`Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/Preset.swift`:

| Preset | Glyph | Pipeline shape | Processors | CaptureControllers (with Parameters) | OutputSinks (with Parameters) |
|---|---|---|---|---|---|
| Dictation | `mic` | `.batch` | `[.transcriber(kind: .asr)]` | `[.manualHotkey, .vad(enabled: .setting(...), …)]` | `[.clipboard(restoreEnabled: .setting(...)), .frontmostPaste(enabled: .setting(...)), .transcriptHistorySQLite]` |
| Notes | `note.text` | `.batch` | same | same | `[.clipboard(...), .frontmostPaste(enabled: .override(false)), .transcriptHistorySQLite]` |
| Meeting | `person.2.wave.2` | `.batch` | `[.diarizedTurns(diarizerKind: .diarization, transcriberKind: .asr)]` | `[.manualHotkey, .vad(enabled: .override(false), …)]` (long-form, no auto-stop) | same as Notes (no auto-paste) |
| Streaming Dictation | `bolt.horizontal` | `.streaming` | `[.streamingTranscriber(kind: .streamingASR)]` | `[.manualHotkey, .vad(enabled: .setting(...), …)]` | `[.clipboard(...), .frontmostPaste(enabled: .setting(...)), .transcriptHistorySQLite]` |

Default-name skip-gaps lives on `WorkflowModeRegistry.nextAvailableName(_:)` (per L-14). View-model orchestrates: `let name = registry.nextAvailableName(preset.displayName); let mode = preset.materialize(name: name); try registry.saveCustom(mode)`.

`Preset.dictation.materialize(name:)` delegates to `WorkflowMode.dictation` literal (replaces id + name).

## Test seams

Per CHECKLIST L-21 (no per-step `swift test`); five behavior tests run in the single-commit close-out. Real `WorkflowModeRegistry` + fake `WorkflowModeStoring`:

| # | Test | What breaks if removed |
|---|---|---|
| 1 | `testDefaultModeFallbackChain` (3 sub-cases: unset / valid / stale) | App-start mode resolution; stale-pointer auto-clear |
| 2 | `testCreatePresetSkipsNameGaps` | Preset creation conflict-resolution |
| 3 | `testSetDefaultRejectsInvalidRecipe` | Validity gating; star-tap can't activate broken mode |
| 4 | `testDeleteDefaultClearsDefault` | `defaultModeID = nil` invariant after delete; `currentMode` falls back to `defaultMode` |
| 5 | `testReorderPersistsThroughStore` | `customModes` array order is the canonical sequence |

Tests added to `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift` (existing file — codex confirmed location).

No view-shape tests, no constant-matches-itself, no mock theater (per L-21).

## Risks (cross-ref CHECKLIST §Anti-patterns)

1. **`activeMode` rename callsites** — 10 sites enumerated in CHECKLIST §Evidence inventory + 3 test fixtures. Pre-commit gate: `grep -rn "activeMode\|activeModeID\|activeModeStream\|mutateActiveOrFork"` returns only `currentMode`/`defaultMode` survivors.
2. **`OutputSinkSpec.frontmostPaste` Codable change** — adds associated value to existing case. Pre-dogfood (L-31), broken decode of foreign documents acceptable. Dev-local docs that decode the new shape will work; older dev docs get reset.
3. **VAD enable gate in orchestrator** — single-line check before VAD wiring. Risk: any other code path that reads `boundRecipe.captureControllers` and special-cases `.vad`. Audit with `grep -rn "case \.vad\|case .vad("` Sources/.
4. **GlobalHotkeyMonitor backward-compat** — `updateRecordingHotkey(_:)` stays for the global hotkey; `updatePerModeHotkeys(_:)` is additive. No callsite churn beyond AppComposition wiring.
5. **AppStore broadcast volume** — `currentModeStream()` fires every menu-bar/pill switcher tap. Same volume as `activeModeStream()` today; equivalent.

## What's deliberately NOT in this plan

- Per-mode model picker (#090) and language picker (#090).
- Per-mode VAD silence threshold (deferred — global only).
- Per-mode clipboard restore delay (deferred — global only).
- LLM step in pipeline (#020/#021/#022).
- Activate-for-apps (#057).
- Persist current across launches (deferred).
- Glyph picker, inline-rename in list, three-column nav.
