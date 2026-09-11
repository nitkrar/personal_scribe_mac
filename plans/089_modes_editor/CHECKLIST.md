# #089 — Modes editor (locks)

Decisions log for the design. Single source of truth for vocabulary, locks, open questions, deferred items, callsite evidence. Subagents and future sessions must respect every L-numbered lock; flag the lock number with a trade-off if challenging it. Locks derive from the 2026-04-28 grilling session + codex design-review-1 corrections.

**Re-spin marker**: this CHECKLIST is the result of review-1 corrections. Review-1 surfaced one critical (placebo per-mode toggles) + three majors (validity truth-source, rename audit incomplete, currentMode concurrency). All four resolved here.

## Vocabulary (locked, verbatim — no synonym invention)

| Term | Meaning | Notes |
|---|---|---|
| **Mode** | A `WorkflowMode` instance in `customModes`. User-facing recipe. | Locked by #078. |
| **Built-in fallback** | `WorkflowMode.dictation` literal in code. Used when `customModes` is empty or `defaultModeID` is unset / stale. **Never rendered in Modes UI.** | New term for #089. |
| **Preset** | A code-defined template the `+` popover applies to seed a new mode. Not a stored type. | Four V1: Dictation, Notes, Meeting, Streaming Dictation. |
| **Default mode** | `defaultModeID: String?` preference in `WorkflowModeDocument`. Set by tapping star on a row. The mode the app starts in. | Renames the existing `WorkflowModeDocument.activeModeID` field. |
| **Current mode** | Runtime state — what the next recording will use. Equals default at app start. Switched via menu-bar / pill switcher (#068). | Persisted only as `defaultModeID`; runtime current is in-memory only. Lives on `WorkflowModeRegistry` under existing `lock.withLock`. |
| **`Parameter<T>`** | **Existing type** at `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift`. Sum of `.setting(SettingKey<T>)` / `.override(T)`. Cascade: `.override` > `.setting` (UserDefaults) > hardcoded default. Resolved eagerly at recipe-build time by `ParameterResolver`. **This is the override-with-default mechanism — do NOT invent `Override<T>`.** | Locked by #078 L19 + L22. |
| **Per-mode hotkey** | Optional field on `WorkflowMode`: `hotkey: HotkeyPreference?`. nil = mode invoked via menu-bar/pill switcher only. Set = a dedicated hotkey activates this mode AND starts recording. | New for #089. |
| **Glyph** | SF Symbol name displayed as the leading icon on a mode row. Fixed-by-preset for V1; stored as `String` field on `WorkflowMode`. | No glyph picker. |
| **Push-nav** | Navigation pattern where the list view is replaced by detail in the same content area, with back arrow in header. | NOT three-column NavigationSplitView. |

## Locks

### Storage / data shape

- **L-1 — `WorkflowMode.dictation` stays in code as fallback only.** Never rendered. Used at runtime if `customModes` is empty or `defaultModeID` points to a deleted mode. **Built-in is never editable; user has no way to mutate the literal.**
  - *Consequence*: GeneralTab Auto-paste / Restore-clipboard / VAD toggle cards **stay** as the canonical "Default" source for the built-in fallback path. Any setting that has a global default must remain global-toggle-accessible because the built-in route consults globals via `Parameter<T>.setting(...)` resolution.
- **L-2 — Modes UI shows `customModes` only.** No section headers, no `BUILT-IN` / `CUSTOM` split, no special row positioning. First launch is empty list with empty-state copy.
- **L-3 — Storage shape is the existing `WorkflowModeDocument` JSON.** `customModes: [WorkflowMode]` already Codable. New fields added (see L-4) are nilable / defaulted so old documents still decode.
- **L-4 — Field changes on persistent types** (single-commit; no migration code per L-31 — pre-dogfood):
  - `WorkflowModeDocument.activeModeID` → renamed to `defaultModeID`. Update doc comment (`WorkflowModeDocument.swift:13-27`) to match.
  - `WorkflowMode` adds `glyph: String` (default `"mic"` on missing-key decode).
  - `WorkflowMode` adds `hotkey: HotkeyPreference?` (nil on missing-key decode).
  - `OutputSinkSpec.frontmostPaste` extended to `.frontmostPaste(enabled: Parameter<Bool>)`. Decode of legacy `.frontmostPaste` (no associated value) defaults `enabled` to `.setting(.autoPasteEnabled)` so it resolves to the existing global pref.
  - `OutputSinkSpec.clipboard` shape unchanged today (`restoreEnabled: Parameter<Bool>` already exists). **Restore-delay is global-only — not a per-mode override.** `ClipboardBatchOutput` continues to read `ClipboardRestoreDelay.resolve()` from defaults directly. Recipe layer carries only the booleans that vary per-mode.
  - `CaptureControllerSpec.vad` extended from current `(silenceThreshold:, showWarning:, showAutoStoppedNotification:)` to add a leading `enabled: Parameter<Bool>`. Decode of legacy `.vad(...)` defaults `enabled` to `.setting(.vadAutoStopEnabled)` so it resolves to the existing global pref. **Resolves codex CHECKLIST-review-1 critical-1**: built-in `WorkflowMode.dictation` literal declares `.vad` unconditionally with `enabled: .setting(...)`; reads from global settings — if user turns Auto-stop off in GeneralTab, recipe resolves to `enabled: false`, orchestrator skips VAD wiring. GeneralTab "Auto-stop on silence" toggle becomes a plain UserDefaults write (no recipe mutation).
  - `BoundOutputSink` correspondingly: `.frontmostPaste(enabled: Bool)` (new). `.clipboard(restoreEnabled: Bool)` unchanged.
  - `BoundCaptureController.vad` correspondingly: gains leading `enabled: Bool`.
- **L-4a — `PreferenceKeys` additions** (resolves codex CHECKLIST-review-1 major-3 + codex DESIGN-review-2 §3 critical): add **two** new `SettingKey`s referenced by L-4 / L-26. Codex DESIGN-review-2 verified `PreferenceKeys.swift:16-45` today has `vadSilenceThreshold`, `vadShowStoppingWarning`, `vadShowAutoStoppedNotification`, `clipboardRestoreEnabled` only. Both `vadAutoStopEnabled` AND `autoPasteEnabled` are missing:
  - `PreferenceKeys.vadAutoStopEnabled: SettingKey<Bool>` — pairs with existing `VadAutoStopEnabledPreference.userDefaultsKey` + `defaultValue`.
  - `PreferenceKeys.autoPasteEnabled: SettingKey<Bool>` — pairs with existing `AutoPasteEnabledPreference.userDefaultsKey` + `defaultValue`.
  - **Constructor signature** is `SettingKey(key:default:)` (NOT `rawKey:`); codex caught this drift.
  - Both must be added in the same commit as L-4 — recipe Codable decode references them in the legacy-decode default path. (`clipboardRestoreEnabled` is already present; reused.)

### Run-time activation model

- **L-5 — Two-state activation.** *Default* (persisted in `defaultModeID`) and *current* (runtime, in-memory). Editor sets default. Menu-bar / pill switcher sets current. They diverge until app restart.
- **L-6 — Reset-to-default on app start.** `currentMode = defaultMode` at launch. If `defaultModeID` unset or stale → `currentMode = WorkflowMode.dictation` (fallback). Persist-across-launches is explicitly out of scope.
- **L-7 — `currentMode` concurrency: under existing `lock.withLock`, NOT `@MainActor`.** Same access pattern as `defaultMode`. Session-start reads happen on the orchestrator path (synchronous, non-main); the registry's existing `NSLock` already serializes those. **No actor isolation.** Codex review-1 §4 resolved.

### Validity gating

- **L-8 — Single availability source for validity, used by all three call sites.** `WorkflowModeValidator` accepts an `availableKinds: Set<ModelKind>` argument. The validity-source rule:
  - **Available kind = a `ModelDescriptor` of that kind whose download phase is `.ready` AND which is currently active (`ActiveModelService.activeDescriptor(for: kind)` returns non-nil)**.
  - All three call sites consult the same source:
    1. `ModesListViewModel` per-row recompute on `ActiveModelService.downloadStates` change.
    2. `WorkflowModeRegistry.setDefault(id:)` server-side validation.
    3. `SessionCoordinator.validateActiveForSessionStart(...)` at session start.
  - *Consequence*: rows can't show valid while session-start fails. Codex review-1 §2 resolved.
- **L-9 — Invalid recipes can be saved but not activated.** Star tap is no-op + warning chip on row. User can still edit the mode toward validity (e.g. download the missing model in AI Models tab).

### UI shape

- **L-10 — Push-nav, not three-column.** Click row body → push detail in same content area; back arrow in detail header dismisses. NavigationStack inside the Modes tab.
- **L-11 — Two row glyphs, separate states.**
  - **Dot** — current-mode indicator. Display-only in editor (set via menu-bar/pill switcher only).
  - **Star** — default-marker. Tappable. Filled = this is the default; outline = not the default.
- **L-12 — Click row body pushes detail. Click star sets default. Click dot is no-op.** Distinct hit areas; never activates from row body.
- **L-13 — Drag-reorder all rows.** Persists as `customModes` array order. Menu-bar / pill switcher iterates this order. No pinning.
- **L-14 — `+` opens preset popover.** Cards: Dictation, Notes, Meeting, Streaming Dictation. Pick → row appended to `customModes` with preset's defaults, push to detail. Default name = preset name with skip-gaps suffix ("Meeting", "Meeting 2", "Meeting 3").
- **L-15 — Inline-editable title in detail header only.** Click → text field → blur saves. NOT inline-rename in list.
- **L-16 — Glyph fixed-by-preset.** No user-pickable glyph. Glyph value populated at create from preset.
- **L-17 — Autosave on every change.** No Save / Cancel / Done. Back arrow only navigates.

### Detail surface (V1 scope)

- **L-18 — Detail shows these settings, in this order:**
  1. Editable title.
  2. Pipeline card: Realtime toggle.
  3. Voice model card: read-only display (active descriptor for the relevant kind) + link to AI Models tab. Per-mode model picker = #090.
  4. Optional processors card: Identify Speakers (diarization) toggle.
  5. Capture card: Auto-stop on silence (Parameter<Bool> picker per L-19; built-in always declares `.vad` per L-4 so the global toggle drives the fallback; threshold uses global pref via `Parameter.setting(...)`, no per-mode threshold V1).
  6. Output card: Auto-paste (Parameter<Bool> picker), Restore clipboard (Parameter<Bool> picker). **Restore delay is global-only — not in this card; lives in GeneralTab.**
  7. Hotkey card: Per-mode hotkey recorder (`hotkey: HotkeyPreference?` field), with "None" / "Set hotkey" affordance.
  8. Delete this mode card at bottom (red trash; confirmation alert; custom-only — every editor row qualifies).
- **L-19 — Parameter<Bool> picker UX**: three-option enum picker per setting. "Default (Live value: On)" / "Force On" / "Force Off". The "Default" option's parenthetical reflects the live UserDefaults value. V1 only ships `Parameter<Bool>` pickers — auto-paste, restore-clipboard, auto-stop-on-silence. No `Parameter<TimeInterval>` pickers in V1 (restore delay + VAD silence threshold stay global-only).
- **L-20 — Voice model picker is read-only display.** Shows the active descriptor for `.asr` (or `.streamingASR` when Realtime is on). Tap → switch to AI Models tab. Per-mode model override is #090.

### Per-mode hotkey

- **L-21 — Per-mode hotkey is an optional field on `WorkflowMode`.** `hotkey: HotkeyPreference?`. nil = no per-mode hotkey (mode invoked via menu-bar/pill switcher only). Set = a dedicated hotkey activates this mode AND starts recording.
- **L-22 — `GlobalHotkeyMonitor` registers global recording hotkey + every mode's per-mode hotkey.** On per-mode hotkey fire: `setCurrent(id:)` + start recording. On global hotkey fire: start recording with whatever is current.
- **L-23 — Hotkey collision detection**:
  - A per-mode hotkey may not collide with the global recording hotkey.
  - A per-mode hotkey may not collide with another mode's hotkey.
  - Reuse existing `SystemHotkeyRegistry` + `ReservedInAppHotkeys` collision check; extend its scope to include all modes' hotkeys.
  - Collision attempts surface inline in the recorder UI (existing pattern).

### Output-path wiring (resolves codex review-1 §1)

- **L-24 — `BoundRecipe.outputSinks` is the single source of truth at delivery; **session-frozen, no live-registry fallback** (resolves codex CHECKLIST-review-1 major-2). `MenuBarSceneModel.deliverBatch(text:)` reads the **session pipeline's frozen `BoundRecipe`** (the same one captured at session start per L-25) and passes the resolved output settings to `OutputService.deliverBatch(text:settings:)`. **Never** falls back to the live `currentMode` mid-delivery — if the user switched mode mid-recording, the in-flight session still finishes with the recipe it started under (mirrors #078 L25 eager-binding). `ClipboardBatchOutput` stops reading `AutoPasteEnabledPreference` / `ClipboardRestoreEnabledPreference` / `ClipboardRestoreDelay` from defaults — uses the passed values.
  - *Edge case*: out-of-session deliveries (e.g. menu-bar "Paste Last Transcript" — `CopyLastTranscriptAction.swift`) don't have a session BoundRecipe. Those use a separate code path that resolves directly from the registry's current mode at action-time. **#089 does NOT change those code paths.**
- **L-25 — Resolution timing**: per-mode parameters resolved eagerly at recipe-build (existing #078 L25). Delivery consumes the already-resolved values. **No lazy reads in the delivery path.**
- **L-26 — Default values for built-in fallback**: `WorkflowMode.dictation` literal uses `Parameter.setting(...)` for every overridable parameter (auto-paste, restore-enabled, restore-delay). Resolves to current global pref → user's GeneralTab Settings UI keeps driving fallback behavior unchanged.

### Cleanup deletions (no consumer after #089 lands)

- **L-27 — `WorkflowModeRegistry.mutateActiveOrFork(...)` is deletable.** Single live caller (`GeneralTab.swift:831`) goes away because GeneralTab toggles now write UserDefaults only — recipes consult the global via `Parameter.setting(...)` resolution.
- **L-28 — `LegacyToggleMigrator` is deletable.** No first-launch migration needed: legacy bool prefs (e.g. `VadAutoStopEnabledPreference`) are preserved as the `Parameter.setting(...)` source. New custom modes default to `Parameter.setting(...)` for these settings; user's pre-#089 toggle values continue to drive behavior automatically.
- **L-29 — GeneralTab cards stay.** Auto-paste, Restore-clipboard, Restore-delay slider, VAD auto-stop, VAD silence threshold all keep their existing UI. The mutation paths simplify (no more `mutateActiveOrFork`); they just write UserDefaults.

### No phasing

- **L-30 — Single-commit close-out.** No phased UI. Either the editor ships complete or it doesn't. Future feature tickets (LLM, app-context, multi-language picker, per-mode model picker via #090) extend the editor as part of their own scope.
- **L-31 — Test cadence: `swift build` only during impl; `swift test` once before commit.** User explicit override of the project's per-step TDD cadence for this feature.

## Evidence inventory (callsite truth, grep-verified 2026-04-28)

**`activeMode` / `activeModeID` / `mutateActiveOrFork` consumers — every site that needs renaming/updating in Step 2:**

| File:line | Type | What changes |
|---|---|---|
| `Sources/PersonalScribeSession/SessionCoordinator.swift:386` | Runtime read | `registry.activeMode` → `registry.currentMode` |
| `Sources/PersonalScribeSession/Pipeline/Contracts/PipelineContextSnapshot.swift:4-15` | DTO field | Field name stays; source becomes `currentMode` |
| `Sources/PersonalScribeSession/Pipeline/PostProcessing/PostProcessingContext.swift:5-20` | DTO field | Same passthrough |
| `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift:543` | DTO passthrough | No change beyond the source |
| `Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:203,272,277,394` | Reads `snapshot.activeMode` | Field unchanged in snapshot |
| `Sources/PersonalScribeAppKit/MenuBar/StatusItemMenuModel.swift:153,198,199` | Label-only `activeModeName` arg | Stays |
| `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTabViewModel.swift:23-62` | Reads `registry.activeMode` + `activeModeStream()` | **File deleted in Step 5** |
| `Sources/PersonalScribeCore/AppStore/AppStoreSnapshot.swift:6,14,21` | DTO field | Field name stays; source becomes `currentMode` |
| `Sources/PersonalScribeCore/AppStore/AppStore.swift:17,63,104,106,170,172,256` | **Load-bearing** — reads `workflowModeRegistry.activeMode` + subscribes to `activeModeStream()` | All 6 hits update to `currentMode` + `currentModeStream()`. The broadcast point that StatusItemController + others observe. |
| `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift:831` | `mutateActiveOrFork` caller (auto-paste toggle bridge) | **Removed** — toggle becomes plain UserDefaults write per L-27 |
| `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift:13-27` | Doc comment cites `activeModeID` | Update doc comment to `defaultModeID` |
| `Tests/PersonalScribeSessionTests/WorkflowMode/WorkflowModeRegistryTests.swift:14-34` | Test fixture sets `activeModeID` | Update fixture to `defaultModeID` |
| `Tests/PersonalScribeAppKitTests/UnifiedWindow/Tabs/ModesTabViewModelTests.swift:43-56` | Test references old VM (file deleted with VM in Step 5) | **File deleted** alongside `ModesTabViewModel.swift` |

**Global pref consumers that the Override resolver path consults (read paths preserved; write paths simplified):**

| File:line | Reads what | After #089 |
|---|---|---|
| `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:76-78` | `AutoPasteEnabledPreference` / `ClipboardRestoreEnabledPreference` / `ClipboardRestoreDelay` from defaults | Stops reading defaults — consumes `BoundOutputSink` resolved values via L-24 |
| `Sources/PersonalScribeAppKit/Settings/VadPreferencePersistence.swift:101` | `VadAutoStopEnabledPreference` + `VadSilenceThresholdPreference` | No change V1 — VAD threshold uses existing `Parameter<TimeInterval>` cascade in `.vad` ProcessorSpec; auto-stop on/off is recipe-shape via `.vad` presence |

**Hotkey consumers — extension points for L-21..L-23:**

| File:line | Role | Change for #089 |
|---|---|---|
| `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift:67` | Single global recording hotkey today | Extend to register per-mode hotkeys + dispatch on fire |
| `Sources/PersonalScribeCore/HotkeyPreference.swift:4` | Type for hotkey storage | Reuse for `WorkflowMode.hotkey` field |
| `Sources/PersonalScribeAppKit/Settings/HotkeyRecorder.swift` | Recorder UI | Reuse in detail card |
| `Sources/PersonalScribeAppKit/Settings/SystemHotkeyRegistry.swift:106` + `ReservedInAppHotkeys.swift:37` | Collision detection | Extend scope to include all modes' hotkeys |

**Cross-ticket references**: only #090 references #089 (depends-on). #056 (streaming dictation) has no current reference but per the codex #056 review, per-mode hotkey ownership for "separate streaming hotkey" lands here in #089 — #056 then scopes to streaming behavior only.

## Open questions (→ for design / impl pass)

- **→** Glyph mapping per preset. Strawman: Dictation = `mic`, Notes = `note.text`, Meeting = `person.2.wave.2`, Streaming Dictation = `bolt.horizontal`. Confirm SF Symbol availability at impl.
- **→** Empty-state copy. Strawman: "No modes yet. Tap `+` to create one."
- **→** Validity warning copy per error case. Strawman in DESIGN.
- **→** Delete confirmation UX (alert vs sheet). Strawman: alert.
- **→** Default-name conflict resolution: skip-gaps locked (L-14); confirm at impl that "Meeting 2" → delete "Meeting 2" → next create produces "Meeting 3" (not reuse "Meeting 2").
- **→** Star affordance details. Filled `star.fill` (champagne) vs outlined `star`; tap radius; no animation V1.
- **→** Where the editor view files live. Strawman: `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/`.
- **→** Per-mode hotkey recorder integration: reuse the existing `HotkeyRecorder.swift` or extract a smaller variant? Lean reuse.
- **→** What happens when the user's global recording hotkey is used while the menu-bar/pill switcher has the user on a mode without its own per-mode hotkey: does the global hotkey just record using the current mode? Yes — global is mode-agnostic (always uses current).

## Deferred / follow-ups

- **#090 — Per-mode model picker + language hint.** Filed.
- **Custom instructions / LLM model picker / Context fields** — separate tickets (#020, #021, #022).
- **Activate-for-apps** — #057.
- **Per-mode VAD silence threshold** — V1 uses global. Could become a per-mode `Parameter<TimeInterval>` if needed; deferred.
- **Per-mode clipboard restore delay** — V1 uses global. Same shape as VAD threshold deferral; revisit if dogfood shows mode-specific delay matters.
- **Persist current across launches** — V1 is reset-to-default. Two-pref upgrade path; revisit if dogfood pain.
- **Glyph picker** — V1 fixed-by-preset.
- **Inline-rename in list rows** — explicitly disallowed (L-15). Detail header only.
- **Three-column NavigationSplitView** — explicitly disallowed (L-10). Push-nav.

## Required reading

1. `plans/089_modes_editor/CHECKLIST.md` (this file).
2. `plans/089_modes_editor/BRIEF.md` — problem statement.
3. `plans/089_modes_editor/DESIGN.md` — architecture + file/type list.
4. `plans/089_modes_editor/IMPLEMENTATION.md` — build steps.
5. `plans/089_modes_editor/089-design-review-1.md` — codex review-1 (1 critical + 3 majors, all resolved here).
6. `plans/investigations/2026-04-28-multilang-feasibility-codex.md` — multilang feasibility (drove split to #090).
7. Existing code, in this priority order:
   - `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift` — the cascade type. **Read first** to confirm "override-with-default" is already shipped.
   - `Sources/PersonalScribeCore/WorkflowMode/ParameterResolver.swift`
   - `Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift`
   - `Sources/PersonalScribeSession/WorkflowMode/BoundRecipe.swift`
   - `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift`
   - `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`
   - `Sources/PersonalScribeAppKit/MenuBar/MenuBarSceneModel.swift`
   - `Sources/PersonalScribeCore/WorkflowMode/WorkflowMode.swift` + `WorkflowModeDocument.swift` + `WorkflowModeRegistry.swift` + `WorkflowModeValidator.swift`
   - `Sources/PersonalScribeCore/AppStore/AppStore.swift` (for the activeMode → currentMode rename)
   - `Sources/PersonalScribeAppKit/Hotkeys/GlobalHotkeyMonitor.swift`

## Anti-patterns — do NOT do these

- **Don't invent `Override<T>`.** `Parameter<T>` is the cascade type; use it. L-vocab.
- **Don't render `WorkflowMode.dictation` in the UI.** L-1 + L-2.
- **Don't add a built-in / custom section header.** L-2.
- **Don't use three-column NavigationSplitView.** L-10.
- **Don't expose Save / Cancel / Done buttons.** L-17.
- **Don't add per-mode model override** alongside per-mode language. L-20 (deferred to #090).
- **Don't phase the UI.** L-30.
- **Don't propose Q.M5 sub-questions as still-open.** Resolved 2026-04-28.
- **Don't run `swift test` per step.** L-31.
- **Don't modify `BoundRecipe.outputSinks` consumers without updating delivery.** L-24 ties them together.
- **Don't `@MainActor`-isolate `currentMode`.** L-7. Use existing `lock.withLock`.
- **Don't delete GeneralTab cards.** L-29. Built-in fallback consults globals via `Parameter.setting(...)`.

## Evidence trail

- Grilling session transcript — implicit in this conversation thread (2026-04-28).
- Reference mockups: `plans/App UI design/` (legacy), `plans/seshat_agent_bundle/03_Surfaces/SettingsWindow/settings_modes.png`, plus user-provided Modes Editor v2 frames + Superwhisper detail screens (in conversation).
- Stale spec being replaced: `plans/PHASE_2_unified_ui.md` Step 2.6 (BLOCKED on Q.M5 since 2026-04-22).
- **Codex review-1**: `plans/089_modes_editor/089-design-review-1.md` — surfaced 1 critical (placebo per-mode toggles) + 3 majors (validity truth-source, rename audit incomplete, currentMode concurrency) + path drift. All resolved in this re-spin.
- **Codex CHECKLIST-review-1**: `plans/089_modes_editor/089-checklist-review-1.md` — surfaced 1 critical (built-in VAD wiring) + 2 majors (L-24 wrong-recipe risk, missing PreferenceKeys SettingKeys). All resolved in L-4, L-4a, L-24. Inventory miss in 3 sites added to evidence table.
- **Multilang investigation**: `plans/investigations/2026-04-28-multilang-feasibility-codex.md` — drove the split of language picker to #090.
