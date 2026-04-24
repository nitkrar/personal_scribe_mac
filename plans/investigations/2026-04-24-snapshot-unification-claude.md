# Snapshot Unification — Step 1 Proposal (Claude)

**Scope:** Bug #072 Step 1 only. Collapse the two parallel clipboard-snapshot
systems into one service. No changeCount-guard wiring, no settings, no UI —
those are Steps 2-5. Step 1 is an internal refactor that leaves observed
behavior identical (Undo still restores; auto-restore still fires
unconditionally after the delay).

---

## 1. Current state audit

The brief's two-system summary is accurate. Concretely:

### System A — `PasteboardSnapshotService` (session-lifecycle)

- **File:** `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:42-91`.
- **Fidelity:** plain string only (`savedString: String?` at line 48; read closure calls `NSPasteboard.general.string(forType: .string)` at line 52; write clears and re-sets `.string` only at lines 54-57). Any non-string payload (RTF, file URL, image, multi-type item) is silently dropped on snapshot.
- **State slot:** single optional slot. Second snapshot overwrites (`PasteboardSnapshotServiceTests.swift:42-52`). `restoreLastSnapshot` consumes the slot on success (line 79); subsequent Undo is a no-op (`PasteboardSnapshotServiceTests.swift:71-90`).
- **Lifecycle / owner:** `PasteboardSnapshotHost` in `PersonalScribeAppMain.swift:443-483`. Subscribes to `AppStore.objectWillChange`, snapshots on `idle → recording` (line 470-472), clears on `transcribing → idle` (line 476-478). `viewModel.onUndoCancelledRecording` calls `restoreLastSnapshot()` (line 456-458) — unconditional write. Owned by composition layer as a `@StateObject`-style host.
- **Consumer:** the pill's Cancel Card Undo button, when user cancels a recording mid-flight.

### System B — `ClipboardBatchOutput`'s inline snapshot (output-pipeline)

- **File:** `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:78-158`.
- **Fidelity:** full `[NSPasteboardItem]` round-trip. `savePasteboard()` at line 140-151 deep-copies each item's types+data; `restorePasteboard` at line 153-158 clears and calls `writeObjects(savedItems)`. Preserves RTF, file URLs, multi-type items.
- **State slot:** **transient local**. `let savedItems` at line 85 is a stack-local inside `deliverBatch`; it is captured by the `scheduleRestore` closure at line 130-135 and by the sync write-failure rollback at line 91. No instance field.
- **Lifecycle / owner:** owned by `ClipboardBatchOutput` the `OutputService`; one `deliverBatch` invocation per transcription. Sync restore at line 91 fires only when `writeString` fails (the transcript never made it to the pasteboard, so the snapshot's safe to slam back immediately). Async restore at line 130-135 fires after `scheduleRestore(restoreDelay, ...)` — unconditional write of `savedItems` back onto the pasteboard. `restoreDelay` is read per-call from `PasteRestoreDelay.resolve(from: defaults)` at line 83.
- **Consumer:** nobody external — the "consumer" is the closure inside `deliverBatch` that fires after the delay expires.

### What the brief didn't flag (worth noting)

- **Neither system captures `changeCount`.** This matters for Step 2's guard; confirming it here prevents a Step-2 surprise. `NSPasteboard.general.changeCount` is nowhere in `Sources/`.
- **The two systems snapshot at different moments** covering different transcript states — System A at the start of recording (pre-recording user clipboard), System B at the start of paste delivery (which, by then, is still the user's clipboard because the transcript hasn't been written yet — line 87 `clearContents()` happens *after* line 85 `savePasteboard()`). So they capture the *same* pre-transcript clipboard, just at two different points in the flow. That means a unified snapshot taken at either moment has the same semantic content **for the happy path**. It diverges only if the user copies something new between recording-start and paste-delivery — a case neither system currently handles (Undo would revert the mid-recording copy, auto-restore would revert it too). Keeping both capture points alive in the unified API would preserve current behavior in that edge case. See risk §5.
- **Test seams diverge.** System A injects `StringReader`/`StringWriter` closures (lines 43-47); System B injects a `PasteboardStringWriter` for the transcript write (line 31) but hits `self.pasteboard` directly for the snapshot/restore read+write (lines 141, 154-157). Tests for System B pass a real `NSPasteboard(name:)` fixture rather than an in-memory fake (`ClipboardBatchOutputTests.swift:10-12`). Unifying the test seam is a Step-1 hygiene win.
- **Anti-pattern already logged:** `BACKLOG.md:781` (#074) calls this exact split out under the state-ownership audit. Unifying here preempts #074 for this slice.

---

## 2. Proposed unified API

### Naming

Keep the name `PasteboardSnapshotService`. The unified purpose ("snapshot + guarded-or-unguarded restore of the system pasteboard") is a strict superset of the old one; rename would be churn without semantic payoff. The service moves to "owns multiple live snapshots," not "owns the Undo snapshot," but that broadening is a contract doc change, not a rename.

### Slot model — keyed multi-slot

One slot is not enough: the Undo path and the auto-restore path can legitimately be in flight concurrently (user kicks off recording → snapshot_A; user stops → transcript delivered → snapshot_B captured; auto-restore fires ~500ms later; user then clicks Undo on the Cancel Card of a *next* recording that started right after). Collapsing to a single slot would cross-contaminate lifecycles.

Resolution: an opaque `SnapshotToken` handle returned at capture time, consumed at restore/discard time. Two slots are live in the steady state (one for the session-lifecycle Undo snapshot, one for the most-recent auto-restore snapshot), but the service doesn't bake those roles in — it's a keyed bag. Callers hold their own token and decide when to restore or discard.

### Token type

`SnapshotToken` is an opaque identifier (value-type, `Hashable`, `Sendable`). It carries the captured `changeCount` internally. Callers do not read the changeCount directly; they pass the token back to the service.

### Method signatures (sketch)

```
@MainActor public final class PasteboardSnapshotService {
    public func snapshot() -> SnapshotToken
    public func restore(token: SnapshotToken) -> Bool              // unconditional
    public func restoreIfUnchanged(token: SnapshotToken) -> Bool   // guarded
    public func discard(token: SnapshotToken)
}
```

- `snapshot()` captures the current pasteboard contents as `[NSPasteboardItem]` (deep copy, same pattern as `ClipboardBatchOutput.savePasteboard()` at `ClipboardBatchOutput.swift:140-151`) plus the current `changeCount`. Returns a token. No external-visible side effect.
- `restore(token:)` writes the captured items back unconditionally and consumes the token (subsequent calls with the same token no-op and return `false`). Returns `true` if the token was live. This is what the Undo path uses — user-initiated, always honored.
- `restoreIfUnchanged(token:)` writes the captured items back **only if** the current `changeCount` still matches the token's captured value. Consumes the token either way. Returns `true` if restore happened. **This API exists in Step 1 but has no caller yet** — Step 2 wires the auto-restore path to use it.
- `discard(token:)` drops the token without writing. Used when a recording completes successfully and the Undo snapshot is no longer needed (replaces `clearSnapshot()`).

### Lifecycle contract

- Tokens are opaque and not persisted; they live as long as the caller holds them.
- `snapshot()` is non-destructive and idempotent-per-moment: two consecutive `snapshot()` calls with no intervening pasteboard change return two distinct tokens with equivalent captured state.
- Restore and discard are terminal operations on a token. The service may keep the backing storage around if another token still references the same snapshot, or not — that's an impl detail, not part of the contract.
- The service does not observe `AppStore` state, does not know about sessions, does not know about paste delivery. It's a pure seam over `NSPasteboard`.

### How the two callers interact with the unified service

**Undo caller (System A replacement — composition layer):**

- `PasteboardSnapshotHost` keeps its `AppStore.objectWillChange` subscription.
- On `idle → recording`: call `service.snapshot()`, store the returned token in `var undoToken: SnapshotToken?` (replaces `savedString` semantics).
- On `transcribing → idle`: if a token is live, `service.discard(token)`, clear the slot.
- On `onUndoCancelledRecording`: if a token is live, `service.restore(token: undoToken!)`, clear the slot. Unconditional. User-initiated.

**Auto-restore caller (System B replacement — inside `deliverBatch`):**

- `ClipboardBatchOutput` gets the service injected (constructor dependency, default-constructed to a shared singleton owned by composition — or more cleanly, a fresh instance per output service, since the service holds no cross-caller state).
- Replace the inline `let savedItems = savePasteboard()` at `ClipboardBatchOutput.swift:85` with `let autoRestoreToken = snapshotService.snapshot()`.
- Replace the sync write-failure restore at line 91 with `snapshotService.restore(token: autoRestoreToken)` (unconditional — we know we never wrote the transcript).
- Replace the `scheduleRestore` closure at lines 130-135 with a call that **still uses the unconditional `restore(token:)` in Step 1**. This preserves current behavior exactly. Step 2 flips that single call site to `restoreIfUnchanged(token:)`.

### State slot model summary

- System-wide: one `PasteboardSnapshotService` instance lives in composition and is injected into both `PasteboardSnapshotHost` and `ClipboardBatchOutput`. Single service, multi-token.
- Internally: the service holds a `[SnapshotToken: CapturedSnapshot]` dictionary. `CapturedSnapshot` bundles `[NSPasteboardItem]` + `changeCount`. Tokens are generated with `UUID()` wrapped in the opaque struct.

### Test seams

Keep the injection style from System A (closures), broadened:

- `pasteboardItemsReader: @MainActor () -> [NSPasteboardItem]` (for snapshot)
- `pasteboardItemsWriter: @MainActor ([NSPasteboardItem]) -> Void` (for restore)
- `changeCountReader: @MainActor () -> Int` (for changeCount capture + comparison)

Defaults match System B's live behavior (deep-copy pattern at `ClipboardBatchOutput.swift:140-151` lifted into the service; `NSPasteboard.general.changeCount` for the reader). Tests pass in-memory fakes (same pattern as `PasteboardSnapshotServiceTests.InMemoryPasteboard` at `PasteboardSnapshotServiceTests.swift:7-9`, upgraded to hold items + a changeCount counter).

---

## 3. Migration sequence

**Strategy: bottom-up, one commit.**

Rationale: the unified service is a strict superset of System A's existing public API (string-only → items-based is a fidelity upgrade, not a contract break for the Undo caller, which only cares that "whatever was there comes back"). The auto-restore caller is equally happy — it used items internally, now it uses items via the service. No intermediate state where Cancel Card Undo is wired to a half-built service. Doing this in two commits would mean either the composition-layer caller or the output-pipeline caller is temporarily on a shim, which is strictly more risk than landing it atomically.

**Single commit, ordered edits:**

1. Extend `PasteboardSnapshotService` to the new API. Internal storage changes from `savedString: String?` to `[SnapshotToken: CapturedSnapshot]`. Add `SnapshotToken` type. Add `restoreIfUnchanged` (implementation is ~3 lines — compare changeCount, delegate to internal restore). Add `changeCountReader` closure with live default. Broaden `read`/`write` closures to items, with live defaults that use the deep-copy pattern from `ClipboardBatchOutput.savePasteboard`/`restorePasteboard`. Old method names (`snapshotCurrentContents`, `restoreLastSnapshot`, `clearSnapshot`) are **removed** — single-slot semantics don't survive the multi-token move. (We could keep them as deprecated single-slot convenience wrappers, but there are exactly two callers and the call-site changes are mechanical; wrappers would be dead weight.)
2. Update `PasteboardSnapshotHost` in `PersonalScribeAppMain.swift:443-483`: add `private var undoToken: SnapshotToken?`, replace three call sites (snapshot on transition-in, clear on transition-out, restore on undo hook). No AppStore subscription changes.
3. Update `ClipboardBatchOutput.deliverBatch` in `ClipboardBatchOutput.swift:78-138`: add `snapshotService` constructor parameter (default-constructed for production); replace the inline `let savedItems` + `savePasteboard()` / `restorePasteboard(_:)` helpers + `scheduleRestore` closure body. Delete the now-unused private helpers at lines 140-158.
4. Update `PasteboardSnapshotServiceTests.swift` to the new API (see §4).
5. Update `ClipboardBatchOutputTests.swift` minimally — inject a fake or real `PasteboardSnapshotService` at each of the 11 `ClipboardBatchOutput(...)` sites. Most test assertions don't touch snapshot internals (they assert on `pasteboard.string(forType: .string)` end-state), so a live `PasteboardSnapshotService` pointed at the test's `NSPasteboard` fixture works with minimal edits. The one test that asserts delay+restore behavior (`testDeliverBatchReadsRestoreDelayPreferencePerCall` at `ClipboardBatchOutputTests.swift:174-219`) needs to verify restore via the new service path; same assertion on final `pasteboard.string(forType: .string)` still holds.
6. Wiring in composition: one `PasteboardSnapshotService()` instance created in `PersonalScribeAppMain`, passed into both `PasteboardSnapshotHost(service:)` and `ClipboardBatchOutput(snapshotService:)`. (Could be two separate instances — nothing in the contract requires sharing. Single instance makes the "one service owns clipboard snapshot+restore" principle visible in the composition graph. Prefer single.)

**Behavior-neutral check, before commit:**

- Cancel Card Undo: captures at `idle→recording`, restores on Undo click, unchanged from observed user experience.
- Auto-restore: captures in `deliverBatch`, restores unconditionally after `restoreDelay`, unchanged from observed user experience. Bug #072's symptom still occurs — that's Step 2's job to fix.
- Fidelity upgrade (string → items) for System A is observable *only* if the user had non-string content on the clipboard before recording, in which case Undo now correctly restores it (previously silently lost). This is a strict win and aligns with the brief's goal #2.

**If the single-commit edit surface feels too large at review time:** fall back to two commits — commit 1 adds the new API alongside the old methods (keeping `snapshotCurrentContents` etc. as thin single-slot shims that internally track one token); commit 2 cuts both callers over and deletes the shims. This loses atomicity but keeps each diff under ~200 lines. Default to one commit; escalate only if review friction demands.

---

## 4. Test impact

### Adapts (behavior preserved, API shape changes)

- `PasteboardSnapshotServiceTests.swift` — all seven tests. `testSnapshotCapturesCurrentPasteboardString` and friends become "snapshot + restore token round-trip" checks. `testSecondSnapshotOverwritesFirst` is **deleted** — two snapshots now yield two independent tokens, not a single overwriting slot. That test codified the old single-slot semantic and is obsolete by design.
- `ClipboardBatchOutputTests.swift` — all 11 constructor sites need the new `snapshotService:` parameter. Most tests' assertions are end-state on the pasteboard and don't need more than that one-line change. The delay+restore test (line 174-219) keeps its end-state assertions.

### Rewrites

- None, strictly. The old "second snapshot overwrites first" test is deleted, not rewritten.

### New tests required for the unified service

- `testRestoreIfUnchangedRestoresWhenChangeCountMatches` — snapshot, no writes, `restoreIfUnchanged` succeeds.
- `testRestoreIfUnchangedSkipsWhenChangeCountBumped` — snapshot, simulate a write (bump changeCount), `restoreIfUnchanged` returns false and does not write.
- `testRestoreIfUnchangedConsumesToken` — second call with same token returns false regardless of changeCount state.
- `testTwoIndependentTokensDoNotInterfere` — capture A, capture B, restore A works; B still valid; restore B works.
- `testDiscardConsumesTokenWithoutWriting` — port of the existing `testClearDiscardsSnapshotWithoutWriting` to the token API.
- `testFidelityIsItemsNotString` — capture a pasteboard with a non-string type (e.g., RTF data on `.rtf`), verify restore brings it back. Codifies the fidelity upgrade.

No test exercises the guarded path through the actual auto-restore caller in Step 1 — there's no caller for `restoreIfUnchanged` yet. That wiring test is a Step 2 deliverable.

### Manual verification

Cancel Card Undo runbook entry (if one exists) should still pass; add a line to confirm non-string clipboard contents also restore. (Grep suggests no dedicated manual runbook for Undo clipboard yet — the feature was string-only and reasonably well covered by unit tests. Can defer runbook addition to Step 2, which touches user-visible behavior.)

---

## 5. Open questions / risks

### Needs user input

1. **Single service instance vs two?** Recommended: single, to make the "one service" goal structurally visible. Alternative: two instances (no shared state anyway). Low stakes; naming the decision so it's not silently made.
2. **Old method name retention as shims?** Recommended: no shims, two callers, mechanical update. Alternative: keep deprecated single-slot shims for one release. Only relevant if external callers exist — none do (confirmed via grep).
3. **Snapshot-moment divergence edge case.** System A captures at recording-start; System B captures at paste-delivery. Unified service captures whenever the caller calls `snapshot()`. In the happy path this is indistinguishable; if the user copies something new between the two moments, the Undo snapshot reverts the copy, and the auto-restore snapshot also reverts the copy. Both parallel systems already do this today — the unification is behavior-neutral *to that edge case*. Flagging in case "both snapshot points should really capture the same moment" turns out to be the spec.

### Risks

1. **Test seam expansion in `ClipboardBatchOutputTests`.** 11 sites × 1 new constructor argument = 11 mechanical edits. Potential for a typo or skipped site. Mitigation: compile-time check — a missing argument fails to build; no silent regression possible.
2. **`changeCount` lives on `NSPasteboard`, not a per-name pasteboard copy.** The test fake needs an explicit `changeCount` counter since in-memory `InMemoryPasteboard` fakes don't auto-track it. Real `NSPasteboard(name:)` does track changeCount correctly (uses pasteboard server), so tests that pass real test-named pasteboards (the `ClipboardBatchOutputTests` pattern) work without extra bookkeeping. Tests that use the in-memory fake (`PasteboardSnapshotServiceTests` pattern) need a `changeCountReader` closure that returns the fake's counter. Straightforward but must not be forgotten.
3. **Concurrency.** Both callers are `@MainActor`; the service is `@MainActor`. No cross-actor hops added. `SnapshotToken` is `Sendable` so it can cross boundaries if future callers need it, but all Step-1 and Step-2 usage is main-actor-only.
4. **The #042 PID probe is load-bearing and lives in `ClipboardBatchOutput`, not in the snapshot service.** Nothing in this proposal touches it. Calling out explicitly so the diff reviewer can confirm no paste-gating logic moved.
5. **No `swift build` / `swift test` run in this worktree** (Santa + AMFI — cf. CLAUDE.md). Compile verification happens at main-session cherry-pick time.

### Not at risk (deliberately)

- Cancel Card Undo semantics. Unconditional restore, user-initiated, unchanged.
- Auto-restore semantics in Step 1. Unconditional restore after delay, unchanged. #072 still reproduces after Step 1 — that's expected. Step 2 is where the guard lands.
- `PasteRestoreDelay` preference. Still read per-call at `ClipboardBatchOutput.swift:83`. Service doesn't own delay.
- `PasteMode` preference and the `clipboardOnly` early-return at line 110-113. Untouched — that branch never captured a snapshot anyway (early return before line 85's `savePasteboard()`).

---

## Summary recommendation

Unify into a single `PasteboardSnapshotService` with a keyed multi-token API returning opaque `SnapshotToken`s that carry captured `changeCount`. Expose three operations — unconditional `restore`, guarded `restoreIfUnchanged` (unused in Step 1, adopted in Step 2), and `discard`. Land in one commit, bottom-up: extend the service, then rewire both callers, then adapt tests. Fidelity upgrades from string-only to `[NSPasteboardItem]` for the Undo path — strict win, no contract break for existing callers.
