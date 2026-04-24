# #072 Step 1 — Clipboard snapshot unification

Step 1 of bug #072's fix plan. Behavior-neutral refactor: fold the two parallel clipboard-snapshot systems into one centralized service. No user-visible change. Step 2 lands the `changeCount` guard that exploits the API this step introduces; Steps 3-6 add prefs, UI, and consolidation.

Proposals that fed this plan:
- `plans/investigations/2026-04-24-snapshot-unification-codex.md` (adopted as base)
- `plans/investigations/2026-04-24-snapshot-unification-claude.md` (host-level test recommendation folded in; API-shape rejected for a latent `changeCount`-timing bug)

## User-locked decisions

1. **Adopt Codex's API shape.** Durable named slot `.cancelUndo` + transient handles + separate `ClipboardWriteToken` returned from the write boundary. Two-token model supports Step 2's guard correctly; single-token models (Claude's) would need the `changeCount` captured post-write, which forces snapshot + write to be one atomic operation owned by the service.
2. **One commit, no legacy adapters.** Sequence inside the commit: extend `PasteboardSnapshotService` with new API → rewire both callers → delete old API. Only two internal callers exist; adapters would be dead weight.
3. **Service owns the pasteboard write boundary.** `replaceContents(with:)` is the only code path that writes the transcript to the pasteboard; `ClipboardBatchOutput` goes through it. The returned `ClipboardWriteToken` carries the post-write `changeCount` that Step 2 will consume.
4. **Full `[NSPasteboardItem]` fidelity** for both callers. System A's string-only behavior was a scope cut, not a design invariant.
5. **"Empty is a real snapshot."** Capturing when the pasteboard is empty produces a valid snapshot whose restore clears the pasteboard. Today System A turns this into a no-op; the unified service makes it consistent with System B's semantic.
6. **Host-level tests land in this commit.** `PasteboardSnapshotHost` has zero direct test coverage today. We're touching it — coverage gap closes here.
7. **#074 framing update on landing.** Once this ships, #074's clipboard-snapshot example is flipped to past tense ("previously fragmented") — don't leave stale anti-pattern references pointing to code that no longer exists.

## Final unified API

```swift
@MainActor public final class PasteboardSnapshotService {
    // MARK: - Durable slots
    public enum Slot { case cancelUndo }

    public func captureCurrentContents(into slot: Slot)
    @discardableResult public func restoreSnapshot(from slot: Slot) -> Bool
    public func clearSnapshot(in slot: Slot)

    // MARK: - Transient handles
    public struct Handle: Hashable, Sendable { /* opaque */ }

    public func captureTransientSnapshot() -> Handle
    @discardableResult public func restoreSnapshot(_ handle: Handle) -> Bool
    @discardableResult public func restoreSnapshotIfUnchanged(
        _ handle: Handle,
        token: ClipboardWriteToken
    ) -> Bool
    public func discardSnapshot(_ handle: Handle)

    // MARK: - Write boundary
    public func replaceContents(with string: String) -> ClipboardWriteToken?
}

public struct ClipboardWriteToken: Equatable, Sendable { /* opaque changeCount */ }
```

### Contract

- **All captures** store a deep-copied `[NSPasteboardItem]` (including empty as `[]`).
- **`replaceContents(with:)`** clears the pasteboard, writes the transcript string, and returns the post-write `changeCount` wrapped in `ClipboardWriteToken`. Returns `nil` only when the pasteboard write itself fails (System B's write-failure rollback still hinges on this signal).
- **Slot capture** overwrites the slot. One slot live at a time per `Slot` case.
- **Slot restore** writes captured items back unconditionally and **clears the slot** (preserves today's "Undo only once" behavior — `PasteboardSnapshotServiceTests.swift:69-89`).
- **Transient handle restore** writes captured items back and consumes the handle. Second call with same handle returns `false` and no-ops.
- **`restoreSnapshotIfUnchanged(_:token:)`** compares the current pasteboard `changeCount` with `token.changeCount`; restores + consumes the handle if equal, otherwise consumes the handle without writing. **No caller in Step 1** — Step 2 adopts it.
- **Transient handles do not alias slots.** Passing a `Handle` to a `Slot` method (or vice versa) is a type error at compile time.

### Test seams

Injectable closures default to `NSPasteboard.general`:

```swift
init(
    pasteboardItemsReader: @escaping @MainActor () -> [NSPasteboardItem],
    pasteboardItemsWriter: @escaping @MainActor ([NSPasteboardItem]) -> Void,
    pasteboardStringWriter: @escaping @MainActor (String) -> Bool,
    changeCountReader: @escaping @MainActor () -> Int
)
```

In-memory test fake tracks items + a bump-on-write `changeCount` counter.

## TDD sequence

Each sub-step is its own test-fix pair inside the single commit (rigid TDD per `seshat/CLAUDE.md`). Tests at `Tests/PersonalScribeAppKitTests/Output/` unless noted.

### 1.1 — Extend service: transient handle round-trip
- **Test** (new, in rewritten `PasteboardSnapshotServiceTests.swift`): `testCaptureTransientSnapshotRoundTripsFullItemFidelity` — capture with RTF + string on pasteboard; write something else; `restoreSnapshot(handle)`; assert both types restored.
- **Fix**: add `Handle`, `captureTransientSnapshot()`, `restoreSnapshot(_:)`. Internal storage `[UUID: [NSPasteboardItem]]`.

### 1.2 — Transient handle consumption
- **Test**: `testRestoreTransientSnapshotConsumesHandle` — capture, restore, restore again returns `false` and no write.

### 1.3 — Transient handle independence
- **Test**: `testTwoTransientHandlesRestoreIndependently` — capture A, capture B, restore A, B still valid, restore B.

### 1.4 — `discardSnapshot(_:)`
- **Test**: `testDiscardConsumesTransientHandleWithoutWriting`.

### 1.5 — Empty snapshot is a real snapshot
- **Test**: `testCaptureEmptyPasteboardRestoresToEmpty` — capture when pasteboard is empty; put string on pasteboard; restore; assert cleared.

### 1.6 — Durable slot API
- **Tests** (replace the old `testSnapshotCapturesCurrentPasteboardString` and friends):
  - `testCaptureIntoCancelUndoSlot` — capture items into `.cancelUndo`, verify retrievable.
  - `testRestoreFromCancelUndoSlotClearsSlot` — restore consumes; second restore returns `false`.
  - `testClearSnapshotInCancelUndoSlotDiscardsWithoutWriting`.
  - `testCaptureIntoSlotOverwritesPrevious` — single-slot semantics for durable slots.
- **Fix**: add `Slot` enum, slot-scoped methods, internal `[Slot: [NSPasteboardItem]]`.

### 1.7 — Fidelity upgrade for slot captures
- **Test**: `testCancelUndoSlotPreservesNonStringItems` — put RTF on pasteboard, capture into slot, write string, restore, assert RTF + original string both restored.
- **Fix**: slot capture uses the same deep-copy path as transient capture.

### 1.8 — Write boundary
- **Tests**:
  - `testReplaceContentsWritesTranscriptAndReturnsToken` — pasteboard ends with only the transcript string; token non-nil; token.changeCount reflects fake's post-write counter.
  - `testReplaceContentsReturnsNilOnWriteFailure` — inject writer returning `false`; result is `nil`, pasteboard unchanged-or-cleared per today's semantic at `ClipboardBatchOutput.swift:89-93`.
- **Fix**: `replaceContents(with:)` clears items, calls writer, returns `ClipboardWriteToken(changeCount: changeCountReader())` on success.

### 1.9 — `restoreSnapshotIfUnchanged` (API lands unused in Step 1)
- **Tests**:
  - `testRestoreIfUnchangedRestoresWhenChangeCountMatches` — capture, write transcript via `replaceContents`, no further writes, guard succeeds.
  - `testRestoreIfUnchangedSkipsWhenChangeCountBumped` — capture, write, bump fake changeCount again, guard returns `false`, no write.
  - `testRestoreIfUnchangedConsumesHandleInBothBranches`.
- **Fix**: implement `restoreSnapshotIfUnchanged(_:token:)`. No production caller wires this in Step 1.

### 1.10 — Rewire `ClipboardBatchOutput`
- **Test updates**: 11 constructor sites in `ClipboardBatchOutputTests.swift` gain `snapshotService:` parameter. Most assertions (end-state on pasteboard) survive; two tests touch snapshot internals and need the seam:
  - `testDeliverBatchReadsRestoreDelayPreferencePerCall` (`:174-219`) — still asserts end-state after delay; route through injected service.
  - `testClipboardOnlyWriteFailureRestoresExistingPasteboardContents` (`:249-279`) — failure-rollback via `restoreSnapshot(handle)`.
- **Fix**: `ClipboardBatchOutput.deliverBatch`:
  - Line 85 `let savedItems = savePasteboard()` → `let handle = snapshotService.captureTransientSnapshot()`.
  - Lines 87-89 `clearContents` + `writeString(pasteboard, text)` → `guard let writeToken = snapshotService.replaceContents(with: text) else { snapshotService.restoreSnapshot(handle); return .failed(.clipboardWriteFailed) }`.
  - Line 91 sync rollback already absorbed above.
  - Lines 130-135 `scheduleRestore` closure body: `snapshotService.restoreSnapshot(handle)`. Keep unconditional (Step 1 scope).
  - Lines 140-158 private `savePasteboard()` / `restorePasteboard(_:)` → **deleted**.
  - Constructor gains `snapshotService: PasteboardSnapshotService` parameter; default `= PasteboardSnapshotService()` retained for direct use.
  - **Note**: the `writeToken` from `replaceContents` is captured but unused in Step 1. Storing it scoped for Step 2 — lint will flag if we bind-and-ignore; use `_ =` with a comment referencing Step 2, or just shadow later. Implementation choice deferred to landing.

### 1.11 — Rewire `PasteboardSnapshotHost`
- **Fix** in `PersonalScribeAppMain.swift:443-483`:
  - Replace `service.snapshotCurrentContents()` with `service.captureCurrentContents(into: .cancelUndo)`.
  - Replace `service.clearSnapshot()` with `service.clearSnapshot(in: .cancelUndo)`.
  - Replace `service?.restoreLastSnapshot()` with `service?.restoreSnapshot(from: .cancelUndo)`.

### 1.12 — Composition wiring
- **Fix** in `PersonalScribeAppMain.swift`:
  - Create one `PasteboardSnapshotService` in `init()`.
  - Pass to `ClipboardBatchOutput(snapshotService:)`.
  - Pass to `PasteboardSnapshotHost(service:)` (already takes `service`; just change the source to the shared instance).

### 1.13 — New host-level tests
- **File**: `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotHostTests.swift` (new).
- **Tests**:
  - `testHostCapturesIntoCancelUndoSlotOnIdleToRecordingTransition` — drive `AppStore.objectWillChange` with fake state transitions; assert `service.captureCurrentContents(into: .cancelUndo)` was called.
  - `testHostClearsCancelUndoSlotOnTranscribingToIdleTransition`.
  - `testHostRestoresCancelUndoSlotWhenUndoClosureFires` — invoke `viewModel.onUndoCancelledRecording`; assert `service.restoreSnapshot(from: .cancelUndo)` was called.
  - `testHostDoesNotCaptureOnOtherTransitions` — e.g. `.recording → .transcribing` is not a capture edge.
- **Seam**: `PasteboardSnapshotHost` takes an injectable spy service that records calls. Spy is a test-only fake conforming to a minimal protocol or subclassing/mocking `PasteboardSnapshotService` (see "Test seams" above — the closure seam lets us observe via side effects).

### 1.14 — Delete old API
- **Fix** in `PasteboardSnapshotService.swift`:
  - Delete `snapshotCurrentContents()`.
  - Delete `restoreLastSnapshot()`.
  - Delete `clearSnapshot()` (single-slot variant).
  - Delete `savedString: String?` storage.
  - Delete `currentSnapshot: String?` test-only accessor.
- **Old test file sections** that called these now fail to compile; they've been rewritten in 1.1-1.9.

## Deletion inventory

- `PasteboardSnapshotService.savedString` (field + all references)
- `PasteboardSnapshotService.snapshotCurrentContents()`
- `PasteboardSnapshotService.restoreLastSnapshot()`
- `PasteboardSnapshotService.clearSnapshot()` (single-slot variant)
- `PasteboardSnapshotService.currentSnapshot` (test-only)
- `ClipboardBatchOutput.savePasteboard()` (private helper)
- `ClipboardBatchOutput.restorePasteboard(_:)` (private helper)
- Old `PasteboardSnapshotServiceTests.swift` string-specific tests (lines 22-124 per Codex audit). Rewritten in 1.1-1.9.

## Manual verification

Runbook entries to append to `Tests/ManualVerifications/` (path TBD — grep finds the right file when we write them):
- **MV-072-S1-1** Cancel Card Undo with non-string clipboard (RTF, file URL) — verifies fidelity upgrade for System A's path. Expected: pre-recording clipboard fully restored on Undo.
- **MV-072-S1-2** Auto-restore after paste with string-only clipboard — verifies System B's observable behavior unchanged. Expected: same behavior as today (including the #072 bug — that's Step 2's job).

## Non-goals (strict)

- No `changeCount`-guard wiring in the auto-restore caller. Step 2.
- No new preferences (`AutoPasteEnabled`, `ClipboardRestoreEnabled`). Step 3.
- No Settings UI consolidation. Step 5.
- No ticket close on #072. Refactor only; #072 symptom still reproduces.

## Santa caveat

Worktree-path `swift test` hits AMFI kills; main-session canonical-path test run happens post-cherry-pick per `project_santa_build_gate.md`. Subagents dispatched for chunks of this plan use `swift build --build-tests` only.

## Commit shape

Single commit, message: `phase-N step N.M: #072 step 1 — unify clipboard snapshot systems`. Files touched:
- `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift`
- `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift`
- `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift`
- `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift`
- `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotHostTests.swift` (new)
