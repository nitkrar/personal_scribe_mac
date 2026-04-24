# Step 1 Proposal: Clipboard Snapshot Unification for #072

## 1. Current state audit

System A is `PasteboardSnapshotService`, and it is currently the Cancel Card Undo path. `PersonalScribeAppMain` creates a `PasteboardSnapshotHost` `@StateObject`, and that host owns a single `PasteboardSnapshotService` instance plus the `AppStore.objectWillChange` subscription that drives it (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:20`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:117-120`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:438-483`). The host snapshots on `.idle -> .recording`, clears on `.transcribing -> .idle`, and wires `PillOverlayViewModel.onUndoCancelledRecording` to an unconditional restore (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:456-477`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift:18-22`, `Sources/PersonalScribeAppKit/Overlay/PillOverlayViewModel.swift:102-110`). The service itself is string-only: the live initializer reads `NSPasteboard.general.string(forType: .string)`, writes with `setString`, stores a single `savedString: String?`, overwrites that slot on each snapshot, and consumes it on restore (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:42-84`). One correction to the brief: the doc comment says snapshot stores `nil` for "empty / non-string", but the implementation simply assigns `read()`, so an empty string would be preserved if the pasteboard exposed one (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:25-31`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:69-71`).

System B lives entirely inside `ClipboardBatchOutput.deliverBatch`. The default `ClipboardBatchOutput` is created in `PersonalScribeAppMain.init` and owns its own pasteboard dependencies, independent of `PasteboardSnapshotHost` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:59-63`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:22-76`). Each `deliverBatch` call deep-copies the full pasteboard into `savedItems` before clearing and writing the transcript; `savePasteboard()` clones every `NSPasteboardItem` and every type's raw data, so fidelity is already full-item, not string-only (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:83-89`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:140-150`). That snapshot is ephemeral state, not a service slot: it is a local `let` captured by immediate write-failure rollback and by the delayed restore closure (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:85-93`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-157`). The brief's summary is right on the "output-pipeline coupled" point, but it missed one important behavior: the same snapshot is also used to roll back immediately when transcript write fails, not just for delayed post-paste restore (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:89-93`).

In the loaded production sources, these responsibilities are isolated to those two owners: `PasteboardSnapshotService` is wired from `PasteboardSnapshotHost`, while `savePasteboard()` and `restorePasteboard(_:)` are private helpers scoped to `ClipboardBatchOutput` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:443-482`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:140-157`). One extra audit note: `ClipboardBatchOutput` still injects `frontmostAppProvider` and `selfBundleIdentifier`, but the current `deliverBatch` decision path reads `pasteMode`, AX trust, `focusedElementIsInAnotherApp`, and `pasteShortcutPoster`, not those bundle-ID dependencies (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:22-32`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:83-137`).

## 2. Proposed unified API

Keep the name `PasteboardSnapshotService`. Step 1 is broadening the existing service's fidelity and ownership, not inventing a new domain; a rename would add churn without clarifying responsibility.

State model: one shared service instance with two storage modes backed by the same deep-copied `[NSPasteboardItem]` snapshot record type.

- Durable named slot: `ClipboardSnapshotSlot.cancelUndo`. This replaces today's `savedString` slot and preserves the session-lifecycle contract that `PasteboardSnapshotHost` already owns (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:48`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:69-84`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:468-477`).
- Transient leased snapshots: an opaque handle allocated per paste attempt. This replaces `ClipboardBatchOutput`'s inline `let savedItems` local and preserves today's ability for a delayed restore to carry its own copied snapshot independently of later output calls (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:85`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-135`).

Recommended surface:

- `enum ClipboardSnapshotSlot { case cancelUndo }`
- `struct ClipboardSnapshotHandle: Hashable`
- `struct ClipboardWriteToken: Equatable`
- `func captureCurrentContents(into slot: ClipboardSnapshotSlot)`
- `func captureTransientSnapshot() -> ClipboardSnapshotHandle`
- `@discardableResult func restoreSnapshot(from slot: ClipboardSnapshotSlot) -> Bool`
- `@discardableResult func restoreSnapshot(_ handle: ClipboardSnapshotHandle) -> Bool`
- `@discardableResult func restoreSnapshotIfUnchanged(_ handle: ClipboardSnapshotHandle, token: ClipboardWriteToken) -> Bool`
- `func clearSnapshot(in slot: ClipboardSnapshotSlot)`
- `func discardSnapshot(_ handle: ClipboardSnapshotHandle)`
- `func replaceContents(with string: String) -> ClipboardWriteToken?`

Contract:

- Every captured snapshot is stored as a deep copy of `[NSPasteboardItem]`, including "empty clipboard" as an empty-item snapshot rather than `nil`. That matches System B's current restore model, where restoring an empty snapshot clears the pasteboard (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-135`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:153-157`), and it satisfies Goal 2's full-fidelity requirement.
- `replaceContents(with:)` is the write boundary for the output path. It clears the current pasteboard, writes the transcript string, and returns the pasteboard `changeCount` observed immediately after a successful write. Step 1 still schedules unconditional restore; Step 2 will only swap the delayed call from `restoreSnapshot(handle)` to `restoreSnapshotIfUnchanged(handle, token:)`.
- Restores are consumptive. Restoring from a durable slot clears that slot after a successful write, preserving today's "Undo only once" behavior (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:73-80`, `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:69-89`). Restoring from a transient handle consumes that handle so delayed restores cannot fire twice.

Caller interactions:

- Undo path: `PasteboardSnapshotHost` keeps its current session-edge logic, but calls `captureCurrentContents(into: .cancelUndo)` on `.idle -> .recording`, `restoreSnapshot(from: .cancelUndo)` from `onUndoCancelledRecording`, and `clearSnapshot(in: .cancelUndo)` on `.transcribing -> .idle` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:456-477`).
- Auto-restore path: `ClipboardBatchOutput.deliverBatch` calls `let handle = snapshotService.captureTransientSnapshot()` before it mutates the pasteboard, `let token = snapshotService.replaceContents(with: text)` instead of keeping inline clear/write logic, restores `handle` immediately if the write fails, and schedules `restoreSnapshot(handle)` after the existing delay if the paste shortcut posts successfully (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:83-93`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:126-135`). Step 1 stores `token` but does not use it yet; Step 2 changes only the scheduled restore call site.

## 3. Migration sequence

I recommend a bottom-up migration in one commit. `PasteboardSnapshotHost` is already behavior-correct for Cancel Card Undo, and `PersonalScribeAppMain` constructs both the output service and the host in one initializer, so a shared instance can be introduced atomically without a risky half-state (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:59-63`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:117-120`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:448-457`).

Suggested order:

1. Expand `PasteboardSnapshotService` in place to deep-copy `[NSPasteboardItem]`, manage one named durable slot plus transient handles, and expose `ClipboardWriteToken`. Keep the current `snapshotCurrentContents()`, `restoreLastSnapshot()`, and `clearSnapshot()` as thin adapters to `.cancelUndo` during the refactor so Cancel Card Undo never loses its working path (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:69-84`).
2. In `PersonalScribeAppMain.init`, create one `PasteboardSnapshotService` instance and inject that same instance into both `ClipboardBatchOutput` and `PasteboardSnapshotHost` instead of letting each path own its own snapshot logic (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:59-63`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:117-120`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:448-452`).
3. Rewire `ClipboardBatchOutput.deliverBatch` to replace `let savedItems = savePasteboard()`, the private `savePasteboard()` helper, and the private `restorePasteboard(_:)` helper with transient-handle calls into the unified service. Preserve current behavior exactly: immediate rollback on write failure, and delayed unconditional restore after a successful synthetic paste post (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:85-93`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-157`).
4. Once the output path is on the shared service, flip `PasteboardSnapshotHost` from the legacy adapter methods to the explicit `.cancelUndo` slot methods. This is mostly an internal call-site cleanup; its lifecycle edges remain the same (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:456-477`).
5. Delete the duplicated batch-output helpers and then, if desired, remove the legacy adapter methods from `PasteboardSnapshotService` in the same commit. I do not see a technical need for a separate compatibility commit because both current construction sites live in `PersonalScribeAppMain.init` and both duplicated helpers are internal to `PersonalScribeAppKit` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:59-63`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:117-120`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:448-452`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:61-64`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:140-157`).

I would only split this into two commits if review appetite, not technical risk, forces it:

- Commit A: expand `PasteboardSnapshotService`, add tests, inject the shared instance.
- Commit B: switch `ClipboardBatchOutput` and `PasteboardSnapshotHost` to the new APIs, then delete duplicate helpers.

Technically, one commit is cleaner because the system has only one moment where "shared instance + no duplicate snapshot logic" becomes true.

## 4. Test impact

`PasteboardSnapshotServiceTests` need the heaviest rewrite because they currently lock in string-specific storage and a `String?` test seam. That includes the string capture assertions (`Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:22-52`), the string restore assertions (`Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:56-100`), and the clear/no-op cases (`Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:103-124`). The consumptive restore and overwrite semantics should stay, but the backing seam should move from `String?` to item snapshots plus write tokens.

`ClipboardBatchOutputTests` mostly survive unchanged where they assert paste gating and delivery outcomes rather than the snapshot mechanism (`Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:20-139`, `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:283-433`). The tests that must adapt are the ones that currently exercise inline snapshot behavior: `testDeliverBatchReadsRestoreDelayPreferencePerCall` (`Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:174-219`) and `testClipboardOnlyWriteFailureRestoresExistingPasteboardContents` (`Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:249-279`). Those should keep their external assertions but route through the shared service seam.

New tests the unified service needs:

- Full-fidelity round-trip of a copied `NSPasteboardItem` with multiple types, proving System A now matches System B fidelity.
- Durable-slot overwrite, restore-once, and clear semantics for `.cancelUndo`, preserving today's Undo contract (`Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:42-52`, `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:69-124`).
- Multiple transient handles can coexist and restore independently, so a second output call cannot corrupt a first delayed restore.
- `replaceContents(with:)` returns a `ClipboardWriteToken` from the successful write boundary.
- `restoreSnapshotIfUnchanged` restores when the current `changeCount` matches the captured token and leaves the clipboard untouched when it does not.
- Explicit empty-snapshot behavior, because the unified service is moving System A from "no string stored" to full-fidelity item capture.

The test inventory above exercises the service directly and the Undo callback at the view-model layer (`Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:22-124`, `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift:20-433`, `Tests/PersonalScribeAppKitTests/PillOverlayViewModelTests.swift:390-417`), while the session-edge policy itself lives in `PasteboardSnapshotHost` via `previousSessionState` and `objectWillChange` (`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:443-482`). If execution changes that host's call signatures, I would add one focused test for `.idle -> .recording` capture and `.transcribing -> .idle` clear rather than relying only on service tests.

## 5. Open questions / risks

1. Empty clipboard semantics need an explicit yes/no before implementation. System B already treats "empty" as restorable by clearing the pasteboard on restore (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-135`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:153-157`), while System A currently turns "no string snapshot" into a no-op (`Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:69-84`, `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:32-40`, `Tests/PersonalScribeAppKitTests/Output/PasteboardSnapshotServiceTests.swift:92-100`). My recommendation is to normalize on "empty is a real snapshot" because that is the only coherent full-fidelity model.

2. The output path should use transient handles, not a second named slot. `ClipboardBatchOutput` currently keeps snapshot state in a per-call local captured by the delayed closure (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:85`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:130-135`); collapsing that into one reusable output slot would introduce overwrite risk if a second output begins before the first delayed restore fires.

3. If you want the unified service to stay strictly "snapshot/restore only", there is a narrower variant where `ClipboardBatchOutput` still performs the pasteboard write and only asks the service to mint or read a `changeCount` token. I do not recommend that variant, because Step 2's guard is safer when the same abstraction both mutates the pasteboard and captures the token immediately after the mutation.
