# 2026-04-26 Security Audit — Lane 5 IPC / Pasteboard / AX (Codex)

> **Provenance note:** Codex's sandbox blocked writes to `plans/investigations/` during the original task (Codex session `019dcbe7-42ee-7ba3-a7bd-98da7542f2da`, task `task-mogc8v7i-ryroha`, completed 2026-04-26 22:34:59Z). Report content recovered verbatim from the codex job log by main session as a transcription artifact.

## 1. Threat-model framing

Within the audited lane files, I observed three IPC surfaces: transcript writes to `NSPasteboard.general` via `ClipboardBatchOutput.deliverBatch(...)` and `PasteboardSnapshotService.replaceContents(with:)` (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-85`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:149-183`), AX trust/PID reads (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:173-203`, `Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceDependencies.swift:61-74`), and synthetic global `Cmd+V` posting (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:139-156`). `deliverBatch(text:)` writes to the global pasteboard before any AX gate runs (`Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:71-85`). Clipboard restore is optional and default-off (`Sources/PersonalScribeAppKit/Settings/ClipboardRestoreEnabledPreference.swift:18-35`); when enabled, the configured restore window is `0.1...10.0s`, default `3.0s` (`Sources/PersonalScribeCore/ClipboardRestoreDelay.swift:12-24`). I found no `NSXPCConnection`, `XPCService`, `NSDistributedNotificationCenter`, `NSPort`, `mach_port`, `NSMessagePort`, or `NSConnection` callsites in the audited lane files.

## 2. Files audited

- `plans/codex-heartbeat-contract.md`
- `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift`
- `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift`
- `Sources/PersonalScribeAppKit/Paste/PasteRouting.swift`
- `Sources/PersonalScribeAppKit/Permissions/OnboardingCompletionObserver.swift`
- `Sources/PersonalScribeAppKit/Permissions/PersonalScribeAppKitPermissionsModule.swift`
- `Sources/PersonalScribeAppKit/Permissions/Service/AppKitPermissionService.swift`
- `Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceAdapter.swift`
- `Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceDependencies.swift`
- `Sources/PersonalScribeCore/Output/OutputDelivery.swift`
- `Sources/PersonalScribeCore/Output/OutputError.swift`
- `Sources/PersonalScribeCore/Output/OutputResult.swift`
- `Sources/PersonalScribeCore/Output/OutputService.swift`
- `Sources/PersonalScribeCore/Output/OutputTarget.swift`
- `Sources/PersonalScribeCore/Output/PipelineShape.swift`
- `Sources/PersonalScribeCore/ClipboardRestoreDelay.swift`
- `Sources/PersonalScribeAppKit/Settings/ClipboardRestoreEnabledPreference.swift`
- `Sources/PersonalScribeAppKit/Settings/AutoPasteEnabledPreference.swift`
- `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift`

## 3. Findings

1. **High** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:76-85`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:101-136`, `Sources/PersonalScribeAppKit/Settings/ClipboardRestoreEnabledPreference.swift:18-35`. **What:** every non-empty delivery writes the transcript to the system pasteboard first, and restore is default-off. **Why:** fresh installs therefore leave transcripts on `NSPasteboard.general` indefinitely, which is sniffable by other local apps. **Mitigation:** make restore default-on with a conservative delay, or gate indefinite retention behind explicit opt-in with a privacy warning.

2. **High** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:41-47`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:94-99`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:57-58`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:102-135`, `Sources/PersonalScribeCore/ClipboardRestoreDelay.swift:12-24`. **What:** the restore path is a best-effort in-process timer, and the pre-transcript clipboard snapshot exists only in memory. **Why:** if the app quits or crashes before the delayed restore fires, the transcript remains on the system clipboard and the original clipboard contents are unrecoverable after relaunch; I did not observe any persisted recovery record or launch-time cleanup path in the audited files. **Mitigation:** persist minimal encrypted recovery state plus a write marker so next launch can restore or clear the app's own clipboard write, or document restore as best-effort only and avoid clipboard use for sensitive transcripts.

3. **Medium** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:78-79`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:94-99`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:57-58`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:102-105`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:138-140`, `Sources/PersonalScribeAppKit/Output/PasteboardSnapshotService.swift:158-167`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:59-68`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:121-127`, `Sources/PersonalScribeAppKit/Composition/PersonalScribeAppMain.swift:491-499`. **What:** `captureTransientSnapshot()` runs on every delivery, but when restore is disabled the code never calls `restoreSnapshot(...)` or `discardSnapshot(...)`. **Why:** because `ClipboardBatchOutput` and the cancel-undo path share one long-lived `PasteboardSnapshotService`, each delivery can leave another deep-copied pre-transcript clipboard snapshot resident in memory for the life of the app; `deepCopy(...)` copies every `NSPasteboardItem` representation, not just strings. **Mitigation:** call `discardSnapshot(handle)` immediately after a successful write when restore is disabled, or only capture transient snapshots when restore is enabled while preserving rollback on write failure.

4. **Medium** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:124-136`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:139-156`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:173-203`. **What:** observed behavior is "AX-check focused PID, then post untargeted global `Cmd+V`." **Why:** this creates a check-to-use gap between the AX read and the actual paste event. Hypothesis: if focus changes in that window, the transcript can paste into a different app or window than the one originally vetted. **Mitigation:** re-read the focused/frontmost target immediately before posting and abort on change, prefer manual paste when target identity cannot be held stable, and add runtime coverage around focus churn.

5. **Info** — `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:139-156`, `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift:173-203`, `Sources/PersonalScribeAppKit/Permissions/Service/PermissionServiceDependencies.swift:61-74`. **What:** in the audited lane files, AX is used only for trust prompting and focused-element PID lookup, and CGEvent injection is limited to a keyboard down/up pair for `Cmd+V`. **Why:** I did not observe AX reads of text/value content, arbitrary keystroke synthesis, or other event classes in the files opened for this audit. **Mitigation:** preserve this narrow surface; any future expansion to AX value reads, non-paste keystrokes, or other event types should get dedicated threat-model review.

## 4. Coverage gaps

- I did not run the app, so I could not verify actual behavior across system sleep/App Nap, crash recovery, or whether the focus-race hypothesis is reproducible in practice.
- I limited code reading to the lane files plus one-hop dependencies needed to establish defaults and object lifetime: `ClipboardRestoreEnabledPreference`, `AutoPasteEnabledPreference`, `ClipboardRestoreDelay`, and the `PasteboardSnapshotService` composition callsite.
- I could not verify how macOS pasteboard APIs behave under partial failure, nor whether crash reports or memory diagnostics could capture the in-memory `NSPasteboardItem` snapshots.
