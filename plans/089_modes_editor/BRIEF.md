# #089 — Modes editor: BRIEF

## Problem statement (user's framing, in conversation)

> we already have dictation, are you saying this is more cluttered mode? If we moved everything to custom what if user deleted every mode, we need some defaults for app to function properly.
>
> assume dictation as the only built in leave the code as is for a worse case fallback if nothing else exist this is what app uses. Consider everything as custom, dictation (builtin) is not showed in modes UI.
>
> Modes UI is a way to define a custom workflow with options of users choosing.
>
> "+" opens a small popover with the named preset cards. sure let's start with this.

## Goal

Ship a complete cohesive Modes editor in the unified window's Modes tab. Users can create, edit, reorder, and delete custom modes (`WorkflowMode` instances stored in `customModes`). The hardcoded `WorkflowMode.dictation` literal stays in code as a runtime fallback only — never rendered. Every mode the user sees is something they created.

Optimize for:

- **Single coherent feature ticket.** No phasing. Either it ships complete or it doesn't (L-20).
- **Autosave-only.** No draft state, no Save / Cancel / Done. Mutations write through `WorkflowModeRegistry` immediately; back arrow only navigates (L-15).
- **Push-nav detail.** Click row body → push detail in same content area; back arrow dismisses. No three-column NavigationSplitView (L-8).
- **Two-state activation.** Default (persisted, set by editor's star) vs current (runtime, set by menu-bar / pill switcher). Reset to default on app start (L-5, L-6).

Avoid:

- Surfacing the built-in fallback in UI. It's an emergency shim, not a row (L-1, L-2).
- Per-row inline rename (L-13). Detail header only.
- Per-mode model override. Voice model stays globally selected via AI Models tab (L-17).
- Phased "v1 / v2" UI states. The editor's surface set = whatever the recipe schema currently expresses (L-16).

## Decisions resolved in the 2026-04-28 grilling session

These are recorded as L-locks in `CHECKLIST.md`. Quick map:

| Q.M5 sub-question (legacy) | Resolution |
|---|---|
| New-mode dialog fields | None — `+` opens preset popover, picks a preset, mode is created with that preset's defaults, push to detail. No dialog. (L-12) |
| Single-active vs multi-active | Single-active. Two states (default + current); only one of each at a time. (L-5) |
| Delete affordance | Detail-card at bottom of detail view, red trash, confirmation alert. Custom-only — every row in Modes UI is custom. (L-16) |
| Built-in editing | Built-in is never editable because it's never rendered. Dictation literal stays in code as fallback. (L-1) |
| Detail surface | Push-nav, back arrow + autosave. (L-8, L-15) |
| Cross-session persistence | Reset-to-default on app start. Two prefs (`defaultModeID` + runtime current) but only `defaultModeID` is persisted. (L-6) |

## Required reading

1. `plans/089_modes_editor/CHECKLIST.md` — every L-lock.
2. `plans/089_modes_editor/DESIGN.md` — architecture + file/type list.
3. `plans/089_modes_editor/IMPLEMENTATION.md` — build steps.
4. Existing code referenced in CHECKLIST.md "Required reading" §6.

## Multi-language picker — gated

If FluidAudio's batch ASR API supports per-call language hint (codex investigation pending at `plans/investigations/2026-04-28-multilang-feasibility-codex.md`):

- Add `language: String?` field on the transcriber `ProcessorSpec`.
- Add `supportedLanguages: [String]?` (BCP-47) on `ModelDescriptor`.
- Detail view shows a Language picker only when active voice model has `supportedLanguages != nil`.

If not feasible, the picker is deferred and a follow-up ticket is filed against FluidAudio for upstream.

## Anti-patterns — do NOT do these

- **Don't render `WorkflowMode.dictation` in Modes UI.** L-1 + L-2. It's a code fallback.
- **Don't add a `BUILT-IN` / `CUSTOM` section header.** L-2.
- **Don't use three-column NavigationSplitView.** L-8.
- **Don't expose Save / Cancel / Done.** L-15.
- **Don't add per-mode model override.** L-17.
- **Don't phase the UI.** L-20.
- **Don't run `swift test` per step.** L-21.
- **Don't propose silent divergence from CHECKLIST locks.** Flag the lock + trade-off in any review or revision.

## Verification — what makes the editor "shipped"

1. First launch on a fresh install: Modes tab is empty with empty-state copy.
2. Tap `+` → popover with four presets → pick Dictation → row appears named "Dictation", glyph = `mic`, push to detail.
3. Detail shows editable title, Realtime off, Voice model = active ASR descriptor (read-only), Auto-stop on, Auto-paste on, Restore clipboard on, Identify Speakers off.
4. Toggling any setting writes through immediately; back arrow returns to list.
5. Tap star → row's star fills; `defaultModeID` persists. Subsequent app start reads it.
6. Drag rows → reorders persist; menu-bar `Mode` submenu (#068 Stage A) iterates the new order.
7. Delete a mode (custom only — every row qualifies) → confirmation alert → row disappears, document persists.
8. Validity violation (Realtime on but no streamingASR downloaded) → row shows warning chip, star tap is no-op until resolved.
9. Full test suite green at commit time (post-#078 baseline + new tests for editor view models, document mutations, default-name conflict resolution, validity gating).
