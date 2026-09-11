# Security Audit — Lane 5: IPC (pasteboard, AX, CGEvent, XPC) — Claude

Date: 2026-04-26
Reviewer: Claude
Scope: read-only audit of IPC seams in the Ninimma codebase. No build, no
test, no commits, no source edits.

---

## 1. Threat-model framing

The transcript leaves Ninimma's process boundary through three sanctioned
IPC seams:

1. **NSPasteboard.general** — system-wide clipboard. Any app on the
   system can read it (`pasteboard.string(forType:)`). Anything Ninimma
   writes is sniffable until the next clipboard write. Restore window is
   the dwell time; after restore, the transcript is replaced by the
   user's pre-transcript clipboard contents (or NOT restored if the
   user disabled restore).
2. **CGEventPost (`.cghidEventTap`)** — synthesized Cmd+V keystroke
   delivered to the HID event tap. This is the paste-at-cursor path;
   the focused app receives a real keyDown/keyUp pair. Vulnerability
   surface: the synthesized event flags / virtual key. If we ever post
   anything other than Cmd+V, we'd be injecting arbitrary keystrokes.
3. **AXUIElementCreateSystemWide / AXUIElementGetPid** — read-only
   AX tree traversal to find the PID of the focused UI element. We
   never set AX attributes or perform AX actions.

There is **no NSXPCConnection, NSDistributedNotificationCenter, NSPort,
NSMessagePort, NSConnection, mach_port** usage anywhere in Sources/ —
verified via repo-wide grep. Ninimma is a single-process app today with
respect to custom IPC.

The pre-transcript clipboard snapshot lives only in process memory
(`[NSPasteboardItem]` arrays in two private dictionaries inside
`PasteboardSnapshotService`); it is never serialized, written to disk,
encoded into UserDefaults, sent to a logger, or copied across an actor
boundary that escapes the service. If the process crashes mid-window,
the snapshot dies with the process — no on-disk residue.

---

## 2. Files audited

- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Paste/PasteRouting.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Permissions/OnboardingCompletionObserver.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Permissions/PersonalScribeAppKitPermissionsModule.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Permissions/Service/AppKitPermissionService.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceAdapter.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceDependencies.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/OutputDelivery.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/OutputError.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/OutputResult.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/OutputService.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/OutputTarget.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/Output/PipelineShape.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/WorkflowMode/OutputSinkSpec.swift`
- `/Users/nitinkum/Projects/nitkrar/personal_scribe/Sources/PersonalScribeCore/ClipboardRestoreDelay.swift`

Cross-cuts (touched but outside the named lane scope, found via grep):

- `Sources/PersonalScribeAppKit/PersonalScribeApp.swift` — has its own
  `defaultClipboardWriter` for the test/legacy shell.
- `Sources/PersonalScribeAppKit/MenuBar/CopyLastTranscriptAction.swift`
  + `MenuBarSceneModel.swift` — menu-bar "Copy Last Transcript" path
  writes the transcript to `NSPasteboard.general`. No restore window
  by deliberate design (see file header).
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift`
  — `PasteboardSnapshotHost` wires `idle ↔ capturing` AppStore
  transitions to the `.cancelUndo` snapshot slot.
- `Sources/PersonalScribeAppKit/Settings/AutoPasteEnabledPreference.swift`
  + `Sources/PersonalScribeAppKit/Settings/ClipboardRestoreEnabledPreference.swift`
  — preferences gating the paste/restore behavior.
- `Sources/PersonalScribeAppKit/Hotkeys/HotkeyEventTap.swift`,
  `Sources/PersonalScribeAppKit/Hotkeys/CGHotkeyEventTapContext.swift`
  — CGEventTap usage. Confirmed read-only / pass-through-or-swallow;
  the tap NEVER posts events. (`HotkeyEvent` adapter only translates
  inbound CGEvents; no `.post(tap:)` calls.)

---

## 3. Findings

### Finding L5-1 — Memory accumulation of clipboard snapshots when restore disabled (MEDIUM)

`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:79-99`
(combined with `PasteboardSnapshotService.swift:102-106` and
`AutoPasteEnabledPreference.swift:22` /
`ClipboardRestoreEnabledPreference.swift:29` defaults).

**What.** Every call to `ClipboardBatchOutput.deliverBatch(text:)` calls
`snapshotService.captureTransientSnapshot()` *before* checking
`ClipboardRestoreEnabledPreference`. The captured handle and the
underlying `[NSPasteboardItem]` array (a deep copy of the user's
pre-transcript clipboard) are stored in
`PasteboardSnapshotService.transientSnapshots[handle.id]`.

The handle is consumed only by `restoreSnapshot(_:)`,
`restoreSnapshotIfUnchanged(_:token:)`, or `discardSnapshot(_:)`. In
`deliverBatch`, the consumption sites are:

- `restoreSnapshot(handle)` on `replaceContents` write failure (line 83).
- `restoreSnapshotIfUnchanged(handle, token: writeToken)` inside the
  `scheduleRestore` closure, called only when `restoreEnabled` is
  `true` (lines 94–99 — the closure short-circuits via `guard
  restoreEnabled else { return }`).

**The default `ClipboardRestoreEnabledPreference` value is `false`**
(file `ClipboardRestoreEnabledPreference.swift:29`, comment "fresh
installs leave the transcript on the clipboard indefinitely"). Therefore
on every fresh install — and every user who never opted into
restore — the snapshot is captured but never consumed. The
`[NSPasteboardItem]` deep-copy persists in `transientSnapshots`
indefinitely, accumulating one snapshot per dictation.

**Why this matters (security framing).** The snapshot's contents are
*the user's pre-transcript clipboard at every dictation moment*. This
includes whatever the user happened to copy before recording — passwords
from a password manager, 2FA codes, private chat excerpts, source
code with secrets. With the leak, every such pre-recording clipboard
state is retained in process memory until terminate. A heap dump,
debugger attach, or memory-disclosure exploit (e.g. CVE-class bug in a
linked dependency) could read all of them. Without the leak, only
the most-recent snapshot would be live for ~3 seconds (the default
`ClipboardRestoreDelay`).

The existing `discardSnapshot(_:)` API on `PasteboardSnapshotService`
is the intended escape hatch but is never called from production
code (verified — only `Tests/PersonalScribeAppKitTests/Output/
PasteboardSnapshotServiceTests.swift:121` uses it).

**Mitigation.** In `ClipboardBatchOutput.deliverBatch`, the
`maybeScheduleRestore` closure should call `snapshotService.discardSnapshot(handle)`
on the `restoreEnabled == false` branch (replace `return` with
`snapshotService.discardSnapshot(handle); return`). Alternatively,
gate the *capture* itself on `restoreEnabled` — if we know we will
never restore, we don't need the snapshot. The latter is cleaner: it
removes the capture cost entirely and matches the user's stated intent
("don't restore"). The former preserves the existing failure-path
rollback (line 83) at the cost of an unnecessary read.

Recommended: gate `captureTransientSnapshot()` on `restoreEnabled`,
since on the failure path (line 83) the rollback is meaningful only
if a write succeeded *prior* to a transcript landing — which is also
gated by `replaceContents` returning a token. Skipping capture when
restore is disabled changes neither the UX nor the failure semantics
(if `replaceContents` fails when capture was skipped, there's no
transcript on the clipboard to roll back from).

### Finding L5-2 — `.cancelUndo` slot snapshot persists across cancelled-recording sessions (LOW)

`Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:518-538`.

**What.** The Combine subscription on `appStore.$snapshot` captures into
`.cancelUndo` on `idle → capturing` and clears on
`transcribing → idle`. If a session goes `idle → capturing → idle`
without ever transitioning through `.transcribing` (e.g. user cancels
the recording before transcription begins, or hold-to-record under
the minimum duration), the `.cancelUndo` slot is *not* cleared. The
captured pre-recording clipboard contents persist in
`PasteboardSnapshotService.slotSnapshots[.cancelUndo]` until the next
`idle → capturing` overwrites it.

**Why.** Same as L5-1, lower severity because (a) the slot only ever
holds *one* snapshot at a time (next recording overwrites), and
(b) cancellation paths do typically result in a follow-up recording.
But the pre-recording clipboard does sit in memory longer than
necessary across session boundaries.

**Mitigation.** Add a transition `capturing → idle` (cancellation /
non-transcription exit) to the clearing branch in
`PasteboardSnapshotHost.init`. The corresponding test asserts current
behavior — needs updating in lockstep. Note: the Cancel Card Undo
flow expects the snapshot to be available *during* the cancel-card
window, so timing matters: clear should happen on the cancel-card
dismissal, not on `capturing → idle` directly. If the cancel-card
dismissal isn't observable, an explicit timeout might be needed.

### Finding L5-3 — Process-exit during restore window leaves transcript on clipboard (INFORMATIONAL — known design tradeoff)

`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:41-46`,
`Sources/PersonalScribeAppKit/MenuBar/StatusItemController.swift:164-173`.

**What.** `scheduleRestore` defaults to `DispatchQueue.main.asyncAfter`.
If the process exits (user-quit, crash, force-quit, SIGKILL, system
reboot, sleep+timeout, OOM) between the transcript write and the
deferred restore, the restore never runs and the transcript remains
on the system pasteboard until another app overwrites it.

The user-initiated quit path is routed through `prequitHandler` in
`StatusItemController.swift:171`, which currently handles
SystemAudioMuter teardown but does NOT flush pending restores.
Force-quit / crash / SIGKILL is acknowledged as out-of-scope at
`StatusItemController.swift:168-169` ("Force-quit / crash / SIGKILL
still leak — accepted scope").

**Why this is informational, not a finding.** This is a deliberate
product tradeoff (pre-#072 commentary in `ClipboardRestoreDelay.swift`
explains the delay-as-tradeoff reasoning), and the user's clipboard is
already known to be sniffable for the duration of the restore delay
(~3s default). Process-exit just extends "until next clipboard write"
into "until next manual user action" — same primitive failure mode,
longer dwell.

**Possible mitigation (not a P1).** The `prequitHandler` could be
extended to synchronously flush any pending restore by clearing the
pasteboard or rewriting the captured snapshot. Doing this would
require `ClipboardBatchOutput` to expose a "drain" API (or a shared
list of pending restores). Tradeoff: adds prequit complexity for a
fairly narrow exposure window.

### Finding L5-4 — `liveFocusedElementIsInAnotherApp` swallows AX errors as "self-focus" (INFORMATIONAL — defensive default is safe)

`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:163-203`.

**What.** When AX is trusted but `AXUIElementCopyAttributeValue`
returns non-success, or `AXUIElementGetPid` returns non-success, the
helper returns `false` ("focused element NOT in another app"). The
caller (line 124) then treats that as "leave on clipboard, don't
paste". This is a fail-safe default: paste is suppressed on AX
failures.

**Why this is informational.** The behavior is correct from a
security stance — failing closed (no synthetic Cmd+V to an unknown
focus) is the right call. The header comment at lines 175–178 names
this explicitly. No mitigation required; flagged here so the next
auditor sees that the choice is intentional.

### Cmd+V synthesis is bounded — confirmed clean

`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:139-158`.

The full set of CGEvent flags posted across the codebase is **only**
this function: `vKey = 9` (the `v` virtual key) with `flags =
.maskCommand` for both keyDown and keyUp, posted to
`.cghidEventTap`. No other site calls `.post(tap:)`. No
`CGEventKeyboardSetUnicodeString` usage. No Unicode-data injection.
No AX `SetAttributeValue` / `PerformAction`. No XPC, mach ports, or
distributed notifications. Cross-process data flow is tightly
restricted to: pasteboard string write + Cmd+V key tap.

The `HotkeyEventTap` (`Sources/PersonalScribeAppKit/Hotkeys/`) is a
read/swallow tap — it observes events headed to other apps and
returns `nil` to swallow ⌥+/ auto-repeat leakage; it never posts
events and never inspects event payload data beyond modifier flags
and key codes.

---

## 4. Coverage gaps

- **No runtime verification.** All findings are static reads. The
  memory-leak claim (L5-1) was not confirmed by attaching a debugger
  and watching `transientSnapshots.count` grow across paste cycles.
  Recommend a one-off heap-graph capture across N dictations with
  `ClipboardRestoreEnabled = false` to confirm.
- **No fuzzing of CGEvent flags.** I didn't trace whether ambient
  modifier-key state on the user's keyboard could leak into
  the synthetic event. Reading the code suggests it cannot
  (CGEvent is constructed fresh with explicit `.maskCommand` only),
  but a test that holds Shift + triggers paste would confirm
  no `Shift+Cmd+V` (paste-without-formatting) flavor variation.
- **No audit of AX permission revocation mid-paste.** If the user
  revokes AX in System Settings between `isAccessibilityTrusted()`
  and `AXUIElementGetPid`, the latter will start failing and
  `liveFocusedElementIsInAnotherApp` returns `false` (paste
  suppressed). Behaviorally correct; not stress-tested.
- **No audit of clipboard-manager interactions.** Apps like
  Paste.app, Maccy, ClipMenu actively snapshot every clipboard
  change. Their snapshots of *Ninimma's* transcript writes are
  entirely outside Ninimma's control, and not in scope here, but
  worth surfacing as an external data-flow Ninimma cannot mitigate
  past the restore window.
- **`PersonalScribeApp.swift` and `PersonalScribeAppMain.swift`
  defaultClipboardWriter** — these write the transcript with
  `clearContents() + setString` but DO NOT capture/restore. Likely
  correct for the menu-bar "Copy Last Transcript" use case (which
  is explicitly "user asked to copy, leave it copied"), but worth
  double-checking that no other callsite reaches these without
  user-initiated copy intent.
- **Snapshot deep-copy uses the system `NSPasteboardItem` API.** I
  did not audit whether `NSPasteboardItem.data(forType:)` can return
  a *promise* that defers loading until the data is requested
  (PromisedPasteboardWriter). If a promise-backed item ages out and
  the deep-copied bytes vanish, restore could leave the clipboard in
  a partially restored state. Not a security finding per se; flagged
  for product correctness.
- **Sandboxing not enforced.** The app is currently unsandboxed (per
  the Santa / DMG signing notes in `~/.claude/projects/.../memory/`).
  An App Sandbox would constrain pasteboard reads to "user-initiated
  paste only", which would change the threat model materially. Not
  a Lane-5 finding; flagged for future scope.
