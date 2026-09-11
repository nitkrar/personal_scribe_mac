# #089 adversarial-review prompt — paste into a fresh codex CLI session at the repo root

Same prompt I dispatched via the rescue subagent (job `task-moj5msek-bbbzzh`, completed in 6m 49s). Reproduced verbatim so you can re-run, refine, or hand to another reviewer.

**Note**: codex's sandbox blocked the file write last run — review content was returned via `/codex:result` and saved manually to `089-design-review-1.md`. If re-running with codex CLI directly (not through the rescue subagent), the sandbox may be more permissive.

---

**Adversarial review of #089 Modes editor plan. Read-only — do not modify code, do not run builds, do not write tests.** Output to `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/089_modes_editor/089-design-review-1.md`. **Hard cap: 12 minutes wall-clock.** Stop conditions: report written + path printed.

# Goal
Red-team the plan. Find what's wrong, missing, or under-engineered. Lead with the strongest objections. Do not pad or hedge. Engineer's bullshit-detector mode.

# Inputs (read in this order)

1. `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/089_modes_editor/CHECKLIST.md` — every L-numbered lock is non-negotiable; flag the lock number with a trade-off if you think one should change. Vocabulary terms locked verbatim.
2. `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/089_modes_editor/BRIEF.md` — problem statement.
3. `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/089_modes_editor/DESIGN.md` — architecture + file/type list.
4. `/Users/nitinkum/Projects/nitkrar/personal_scribe/plans/089_modes_editor/IMPLEMENTATION.md` — build sequence.

Reference (the codebase the plan operates against):
- `Sources/PersonalScribeCore/WorkflowMode/` — current registry, document, validator, mode types
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/ModesTab.swift` + `ModesTabViewModel.swift` — current placeholder
- `Sources/PersonalScribeAppKit/Settings/GeneralTab.swift` — gets pruned
- `Sources/PersonalScribeAppKit/MenuBar/StatusItemMenuModel.swift` — Mode submenu (#068 Stage A); plan switches it from `activeMode` → `currentMode`
- `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` + `LegacyToggleMigrator.swift` (slated for delete) + `BoundRecipe.swift`
- `Sources/PersonalScribeSession/Models/Selection/ActiveModelService.swift` — observed for validity recompute
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` — `validateActiveForSessionStart` callsite

# What to attack

For each, find the strongest objection. If you can't find one, say "no objection" and move on — don't manufacture concerns.

1. **Are any L-locks contradictory or overconstrained?** Pay special attention to L-1 (built-in fallback never rendered) interacting with L-7 (validity) and L-8 (push-nav). Specifically: when `customModes` is empty AND user opens Settings → Modes, what does the user see? When the StatusItemMenuModel Mode submenu is opened with empty customModes, what does it show?

2. **Field rename without migration (L-4) — are there callsites the plan misses?** Grep aggressively for `activeMode`, `activeModeID`, `mutateActiveOrFork`. Find any consumer outside the listed call sites in IMPLEMENTATION.md Step 2 + Step 6.

3. **`currentMode` runtime state — semantics under concurrent access.** `WorkflowModeRegistry` uses `lock.withLock` for document mutations. The plan adds `setCurrent(id:)` (in-memory only). Does the plan introduce a race between `setCurrent(id:)` and `deleteCustom(id:)` if user deletes the mode the menu-bar just selected? Does `setCurrent` need to be locked?

4. **GeneralTab toggle deletion — UX regression?** Today users have a global Auto-paste toggle. Plan removes it; user must edit each mode. Is there a hidden migration path (existing user's `AutoPasteEnabledPreference` value) that should be honored? Or is the user explicitly OK with that being lost (pre-dogfood)? Check `Sources/PersonalScribeCore/Preferences/` for what preferences are read elsewhere.

5. **`ModesListViewModel` validity recompute — is the trigger graph complete?** Plan says recomputes on (a) `WorkflowModeRegistry` broadcast, (b) `ActiveModelService.downloadStates`. Are there other state changes that would invalidate row validity? E.g. a model being deleted, a streaming model finishing download, ASR adapter prepare failing. Does the plan miss a subscription?

6. **`Preset.dictation.materialize(name:)` delegates to `WorkflowMode.dictation` literal.** Is that delegation safe given `WorkflowMode.dictation` lives in Core and `Preset` lives in AppKit? Does AppKit already import Core? Is there a circular-dependency risk?

7. **Drag-reorder + `setDefault` race.** User drags a row WHILE `setDefault` is in flight (writes document). Plan's `reorderCustom` also writes document. Both grab `lock.withLock`. Is the order they serialize in compatible with the user's intent? E.g. set-default-on-row-A, then drag-reorder-A-to-position-2 — does the document end up with `defaultModeID = A.id` AND `customModes` reordered?

8. **Test set adequacy.** Five tests in IMPLEMENTATION.md Step 7. Is there a behavior the plan ships that isn't covered? Conversely — is any of the five tests a constant-match-itself or shape-test in disguise (per L-21)?

9. **`mutateActiveOrFork` deletion — really no callers outside GeneralTab?** Grep. If there are other callers, the plan is incomplete.

10. **First-launch experience.** First-ever user opens the app. Modes tab is empty per L-2. Tries to record via hotkey — what happens? Plan says fallback to `WorkflowMode.dictation`. Is the orchestrator + session start path actually wired to fall back when `customModes` is empty AND `defaultModeID` is nil? Cite the path.

11. **Single-commit close-out under L-21 — realistic?** Plan estimates ~9 file modifications + ~9 new files + ~4 deletions in one commit. With no per-step `swift test`, how does the implementer catch a regression introduced in Step 2 that breaks Step 5? Is the plan robust to a multi-day implementation across multiple sessions?

12. **The five "open questions" in CHECKLIST §"Open questions"** — are any of them decisions the plan implicitly makes but doesn't lock? E.g. "Validity warning copy per error case" — DESIGN proposes copy, but is it locked or open?

# Output format

Use this exact structure:

```markdown
# #089 design review 1 — codex

## Summary
≤ 80 words. Lead with the strongest 2-3 objections.

## Objections (ranked, strongest first)

### 1. <one-line title>
**Severity**: critical | major | minor
**Where**: file:line or DESIGN/IMPLEMENTATION section
**Issue**: ≤ 80 words.
**Suggested fix**: ≤ 60 words.

### 2. <...>

(...repeat per objection...)

## No-objection items
List the attack vectors above where the plan holds up. One line each.

## Plan-vs-code drift
Anything in DESIGN/IMPLEMENTATION that doesn't match current `Sources/` shape (e.g. cited file path doesn't exist, cited method has different signature). One line each.
```

# Hard rules

- Severity = critical only if the plan as written ships a bug or fails to compile. Don't inflate.
- Cite file paths + line numbers for every claim about current code.
- Do NOT propose new features. Stay in scope.
- Do NOT rewrite the plan. Surface objections; the main session re-decides.
- ≤ 600 words total. Trim before submitting.
- If you can't find an objection in a category, write "No objection — <one-line reason>" instead of inventing one.
