# #089 Modes editor — fresh session handoff prompt

Paste the section below into a fresh Claude Code session at `/Users/nitinkum/Projects/nitkrar/personal_scribe`. The plan is locked + triple-reviewed; your job is sequential execution.

---

You're picking up #089 (Modes editor). The plan is fully specified and triple-reviewed. The prior planning session ran out of context budget; you have full context for the actual code work.

## Mandatory reading (in this order, all under `plans/089_modes_editor/`)

1. **`CHECKLIST.md`** — every L-numbered lock (L-1 through L-31). Non-negotiable. If you think a lock should change, surface the lock number with the trade-off and stop until I confirm. Don't silently pivot.
2. **`DESIGN.md`** — architecture, schema deltas, file/type list. Cite this for every code shape decision.
3. **`IMPLEMENTATION.md`** — 9-stage build sequence (A through I). Strict adherence; deviate only on critical issues, and surface those before deviating.
4. **`089-design-review-1.md`** + **`089-checklist-review-1.md`** + **`089-design-review-2.md`** + **`089-implementation-review-1.md`** — codex adversarial reviews. ALL findings already addressed in the locked plan; read for context, don't re-litigate.

## In-flight ownership

I'm session `cedar`, ticket already flipped to `in-progress` in `BACKLOG.md` row. Inherit that ownership; bump the `Last update` cell when you commit. Per project convention, do **NOT** stage `BACKLOG.md` in the commit unless I explicitly ask.

## Locked premises (most likely to be re-litigated; don't)

- `WorkflowMode.dictation` literal stays in code as fallback ONLY. Never rendered in Modes UI. Built-in fallback recipe declares `.vad(enabled: .setting(.vadAutoStopEnabled), ...)` and `.frontmostPaste(enabled: .setting(.autoPasteEnabled))` so global GeneralTab toggles drive fallback behavior unchanged.
- GeneralTab Auto-paste / Auto-stop / Restore-clipboard / VAD-threshold cards **stay**. They become plain UserDefaults writes (drop `mutateActiveOrFork` calls in three setters at `GeneralTab.swift:725,755,786`). Recipe layer reads via `Parameter.setting(...)` cascade.
- `Parameter<T>` is the existing override-with-default cascade type at `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift`. **Do not invent `Override<T>`** — it would be a synonym.
- Two new SettingKeys to add at `PreferenceKeys.swift`: `vadAutoStopEnabled` and `autoPasteEnabled`. Constructor is `SettingKey(key:default:)` (NOT `rawKey:`). Pair with existing `VadAutoStopEnabledPreference.userDefaultsKey` / `defaultValue` and `AutoPasteEnabledPreference.userDefaultsKey` / `defaultValue`.
- `BoundOutputSink` MOVES from `PersonalScribeSession/WorkflowMode/BoundRecipe.swift` to a new file `PersonalScribeCore/WorkflowMode/BoundOutputSink.swift`. Otherwise `OutputService.deliverBatch(text:sinks:)` (Core protocol) referencing it would create a circular dep — Session already imports Core.
- `WorkflowModeRegistry` is split: `defaultMode` (persisted via `defaultModeID`) + `currentMode` (in-memory only). `setActive(id:)` and `mutateActiveOrFork(...)` are DELETED. Both `defaultMode` and `currentMode` reads under existing `lock.withLock` — NOT `@MainActor` (the registry stays under NSLock per L-7).
- `SessionCoordinator` is an actor; field is `pipeline` (NOT `orchestrator`). The new `currentBoundRecipe()` accessor is `async`: `await pipeline.currentBoundRecipe()`. `MenuBarSceneModel.deliverBatch` adds the `await`.
- Multi-language picker + per-mode model picker → **#090** (separate ticket, already filed). `BACKLOG.md:920` for the body. Do not bundle.

## Execution discipline (per L-30, L-31)

- **Sequential in this session.** No subagents. No worktrees. Cross-cutting work fits cleaner in one head.
- **Test cadence**: `swift build` only between stages as a sanity check. Do NOT run `swift test` per stage. Full suite runs once before commit (Stage I.2).
- **Single commit at close-out.** Commit message format: `phase-N step #089: ship Modes editor (custom recipes, push-nav detail, autosave)`. Body references CHECKLIST L-locks honored + reviews resolved.
- **Pre-dogfood**: broken decode of dev-local `workflow-modes.json` after the field rename is acceptable (L-31). No migration code.

## Test discipline — no fluff

The 7 new behavior tests (H.1, H.2, H.3, H.4, H.5, H.6, H.7) + 1 rename (H.3 in old plan, now `testSetDefaultValidatesAvailableKinds`) are listed in IMPLEMENTATION.md Stage H. Each row carries a "Why not fluff" justification. **Do not add tests beyond that list.** If you find yourself wanting to write a test for a constant, a getter, a shape match, or something a refactor would only break if it actively broke product behavior — DON'T. Surface the gap to me first.

Manual verification entries (`MV-MODES-1` through `MV-MODES-12`) go in a NEW file `Tests/ManualVerifications/ManualModesVerification.md`.

## Worktree caution (if you must spawn anything)

Plan says no agents. If a critical divergence makes you want to spawn one anyway:
1. Run `git rev-parse HEAD` immediately before spawn; record that SHA.
2. Brief the agent with the SHA + "your worktree is at commit X; main may have moved since."
3. After the agent returns, verify its commits don't reach beyond declared scope.
4. NEVER run `swift test` from a worktree (Santa popups). `swift build --build-tests` only.

## Definition of done

- All 9 stages (A-I) in IMPLEMENTATION.md complete.
- `swift test` from canonical repo path: full suite green (1080+ baseline + 7 new).
- Manual checklist `MV-MODES-1` through `MV-MODES-12` exercised in DMG.
- `git diff --stat` reviewed; no surprise files.
- `grep -rn "activeMode\|activeModeID\|activeModeStream\|setActive(id:\|mutateActiveOrFork\|LegacyToggleMigrator\|ModeCard" Sources Tests` survivors are ONLY the 4 DTO `activeMode` field references on `AppStoreSnapshot`/`PipelineContextSnapshot`/`PostProcessingContext` (renamed source, field stable).
- Single commit landed on `trunk`. Don't push.
- Update `BACKLOG.md` `#089` status `in-progress` → `done`; bump *Updated* line; remove the in-flight row. (Don't stage BACKLOG.md unless I ask.)

## What to surface to me before continuing

- Any lock you think should change (with lock number + trade-off).
- Any test you think is missing from the H.1-H.7 list (with what would silently break).
- Any file path in IMPLEMENTATION.md that doesn't match current code (rare — I grep-verified at write-time, but Swift packages drift).
- Compile failures that don't trace to a stage's expected churn.

Don't surface for: silent design decisions you make consistent with the locks, mechanical renames, test fixture updates that follow from B.2's enumerated list.

---

Ready? Read CHECKLIST → DESIGN → IMPLEMENTATION in order, then start Stage A.
