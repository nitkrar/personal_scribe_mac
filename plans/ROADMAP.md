# Ninimma — Roadmap

**Goal:** Evolve Ninimma in four product-state milestones — stable daily dictation → unified visual identity → full personal-scribe features → intent-aware assistant.

**Phase gate semantics:** Each phase has a definition-of-done. Phases are product-state milestones, never calendar dates. Do not start Phase N+1 work until Phase N's gate is met.

**Backlog location:** active items in [`BACKLOG.md`](../BACKLOG.md); closed items in [`BACKLOG_ARCHIVE.md`](../BACKLOG_ARCHIVE.md). Each ticket's `phase:` tag is the canonical phase scope.

---

## Phase map

| Phase | Name | State | Definition-of-done |
|---|---|---|---|
| **1** | Stability + foundational refactors | ✅ done on trunk | Daily-dictation reliable (record → stop → auto-paste every time); all P0/P1 BACKLOG items resolved or explicitly deferred; registry + base-dir refactor merged; in-memory history available; permission UX informative. |
| **2** | Unified architecture + visual identity | ✅ done on trunk | New design system (theme + quill logo + waveform + core components) shipped; pill overlay supports the three visibility modes; native `NSMenu` menu bar; dark/light palette applied; custom app icon in place. |
| **3** | Features + polish | 🔧 in progress | `NotesWindow` + `SettingsWindow` (Modes tab) + `OnboardingWindow`; SQLite-backed transcript history with FTS5 search (via #026); base-dir migration UI; hotkey customization; second model descriptor available. A new user can install the DMG, complete onboarding, select a mode, record for weeks, and search past transcripts. |
| **4** | Intent layer + assistant | — future | `IntentClassifier` online; Command Mode response cards; Notes surface as personal knowledge base; llama.cpp / Apple Foundation Models integration; "Ask Ninimma" query flow; Action Dispatcher. |

---

## Cross-cutting rules

Apply to every phase. See [`~/.claude/CLAUDE.md`](~/.claude/CLAUDE.md) global operating principles + project `CLAUDE.md` for full discipline.

1. **TDD required.** Failing test first for every bug/feature. UI that can't be XCTest'd requires a manual-verification checklist entry in the relevant `Tests/*/Manual*Verification.md` before shipping.
2. **Don't overclaim.** `swift build` succeeding ≠ feature works. Distinguish committed / built / tested / runtime-verified; only the last earns "done" / "shipped".
3. **Minimise rebuild friction.** Batch related changes so a phase produces ~3 rebuild cycles, not N. Each DMG rebuild costs a Gatekeeper reapproval round.
4. **Don't flip-flop.** Parakeet/FluidAudio choice stays unless new technical data overrides it. Same for other locked decisions — classify before pivoting (new data → pivot; predictable consequences of a prior decision → defend).
5. **Backward-compat at API boundaries.** New fields/columns are optional. Missing migration must not crash the app.
6. **Semantic audit before phase gate.** Grep for forbidden-duplicate patterns the phase was supposed to eliminate. Inventory declarations by semantic role, not by name.
7. **Commit subject format:** `phase-N step N.M: <verb-led subject>` for phase-tagged work, or `trunk: <ticket-ref or subject>` for untagged work. Test + fix go in the same commit when TDD applies.
8. **Santa caveat.** Main repo path runs `swift test` clean under Lockdown + Transitive Allowlisting. Worktree paths (`.claude/worktrees/…`) are NOT covered — worktree agents must use `swift build --build-tests` only, never `swift test`.

---

## Phase scope

Open work for a phase is every ticket tagged with it: `grep -n 'phase: 3' BACKLOG.md`. For Phase 3 that is tags (#014), the disk-space precheck (#025), the personal dictionary (#045), active-window context capture (#048), the in-pill mode switcher (#068 Stage B) and recording-persistence follow-ups (#069). Phase 4 is a direction, not a plan: intent classification, Command Mode, "Ask Ninimma", the action dispatcher, meeting mode and assistant features, revisited once Phase 3 ships.
