# Ninimma — Roadmap

**Goal:** Evolve Ninimma in four product-state milestones — stable daily dictation → unified visual identity → full personal-scribe features → intent-aware assistant.

**Phase gate semantics:** Each phase has a definition-of-done. Phases are product-state milestones, never calendar dates. Do not start Phase N+1 work until Phase N's gate is met.

**Backlog location:** active items in [`BACKLOG.md`](./BACKLOG.md); closed items in [`BACKLOG_ARCHIVE.md`](./BACKLOG_ARCHIVE.md). Step-level scope that used to live here has been unbundled into tickets and removed — see the per-ticket `phase:` field.

**Central-layers refactor:** plans at [`central/`](./central/); remaining validation tracked by ticket **#031**.

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

## Phase 3 in-flight summary

Tickets currently carrying `phase: 3`:

- **#009** — FluidAudio model-download progress (Stage B, P0) — blocks clean first-launch UX
- **#011** — Per-row delete on history (depends on #026)
- **#013** — NotesWindow (P1, depends on #026)
- **#014** — Tags (P1, depends on #026 + #013)
- **#015** — OnboardingWindow (P2)
- **#016** — Second model descriptor parakeet-tdt-110m (P2)
- **#017** — Hotkey customization + collision detection (P2)
- **#018** — Clipboard clobber timing (P3)
- **#019** — Triple-tap ⌥ emergency quit (P3)
- **#024** — Per-row model delete button (P2)
- **#025** — Disk-space precheck (P2)
- **#026** — **Central storage/database layer** (P1, in-progress, blocks #011/#013/#014/#022/#027)

**Critical path for Phase 3:** #026 (storage layer) → #013 (Notes) → #014 (tags). #009 is independently P0 because it's a dogfood-blocker symptom, not a feature.

---

## Phase 4 scope sketch

Not a plan — a direction. Revisit after Phase 3 ships and dogfood feedback accumulates on intent-style flows. Tickets carrying `phase: 4`:

- **#020** — `IntentClassifier`; NLEmbedding-based first, escalate to llama.cpp local LLM when ambiguous
- **#021** — Command Mode pill response cards (query answer / action confirmation / dictation)
- **#022** — "Ask Ninimma" query flow wired to Notes FTS5 + embedding lookup
- **#023** — Action Dispatcher (NSWorkspace + app-specific APIs)
- **#027** — `TranscriptEntry` schema evolution (`modeId` + `trigger`) — driven by Command Mode stressing the schema
- **#038** — Second "AI models" settings section (LLM downloader surface)
