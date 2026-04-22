# #042 AX probe review — Claude pass (2026-04-22)

## Root cause confirmation

The probe at `ClipboardBatchOutput.swift:220-259` returns `true` only when the system-wide focused element exposes `kAXInsertionPointLineNumberAttribute`, `kAXSelectedTextAttribute`, or one of three standard text roles (`kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`). Sublime Text renders its editor surface into a custom NSView backed by its own OpenGL/Metal draw — it does not subclass `NSTextView` and therefore does not inherit the AX accessors that supply the three attributes above. Its AX role is typically `AXGroup` or `AXUnknown`. This matches the manual observation at `ManualPillOverlayVerification.md:183-185` ("Sublime Text triggers the card due to a separate AX-probe regression — tracked as BACKLOG #042"). VS Code (Electron) and Chrome form fields sit behind `AXWebArea` / `AXGroup`; when their inner text field does surface `AXTextArea` the probe works, but many Electron controls stop the walk at `AXGroup`. So the probe is under-inclusive for custom-drawn editors and every fix option must widen the permissive set OR replace the probe with a different signal.

## Option 1 — PID inequality

- **Concrete mechanism.** Query the system-wide focused element (as today), then call `AXUIElementGetPid(focused, &pid)` — a C function in `ApplicationServices`, not an AX attribute. If `pid != getpid()` (self), paste. Replaces the attribute/role gate entirely.
- **Pros.** Small, robust to custom-drawn editors. No false negatives from role taxonomy gaps. Self-contained (no new deps).
- **Cons / failure modes.** Any focused element in another app counts as paste-eligible — Finder sidebar rows (`AXOutline`), Spotlight results, Notification Center items, the Dock. User hits the hotkey with focus on Finder sidebar → transcript is pasted as `Cmd-V` into Finder, which interprets it as a filename typed into the current folder. Similar for message-list panes in Mail. This is a real regression, not hypothetical.
- **Feasibility: medium.** Simple code change, but widens the "paste anywhere outside self" blast radius substantially. Acceptance criterion 2 ("card only appears when focused element is genuinely inside Ninimma") would be met too strictly — non-text surfaces would also receive paste.

## Option 2 — extended roles

- **Concrete mechanism.** Keep cursor/selected-text attribute checks. Extend accepted roles to include `kAXGroupRole`, `kAXUnknownRole`, `kAXWebAreaRole` conditional on `AXUIElementGetPid(focused) != self.pid`.
- **Pros.** Fixes Sublime and most Electron editors; retains "no paste when Ninimma owns focus" defense at the AX layer.
- **Cons / failure modes.** `AXGroup` is one of the most common AX roles in all of macOS — it wraps toolbars, sidebar containers, non-text layout blocks in every app. Same for `AXUnknown` (custom views with no role set). `AXWebArea` wraps the entire Safari/Chrome page, including non-form pages — pasting into a read-only WebKit content view does nothing but still fires `Cmd-V`. False-positive rate climbs sharply.
- **Feasibility: low.** The role extension does not distinguish text-receptive from non-text surfaces. Would need a secondary signal (e.g. also requires a child with `AXTextArea`) to avoid noise — at which point the probe is becoming a walker, not a gate.

## Option 3 — revert to bundle-ID

- **Concrete mechanism.** Restore the rollback block at `ClipboardBatchOutput.swift:154-165`. Paste whenever `NSWorkspace.shared.frontmostApplication?.bundleIdentifier != AppBrand.bundleIdentifier` (`Sources/PersonalScribeCore/AppBrand/AppBrand.swift:5`). Drop the `focusedElementHasCursor` guard.
- **Pros.** Verbatim pre-2026-04-20 behavior; previously shipped working for every app including Sublime. Simplest diff (delete probe, reinstate `resolveTarget`). No probe maintenance going forward.
- **Cons / failure modes.** Loses the "cursor actually present" safety net. Any path that makes Ninimma the `NSRunningApplication.frontmost` during the paste window regresses to the #003 symptom — clipboard-only card instead of paste.
- **Feasibility: high**, conditional on the regression audit below coming back clean.

## Alternative options

- **Option 4 — parent-chain walk.** From the focused element, walk `kAXParentAttribute` up to N levels looking for a text-receptive role. Useful for Electron (inner `AXTextArea` under outer `AXGroup`) but doesn't help Sublime, which has no `AXTextArea` descendant at all. Not worth adopting alone.
- **Option 5 — defense-in-depth OR.** Paste when **either** the AX probe succeeds **or** the frontmost-bundle-ID is not self. The AX probe remains a positive signal for apps that do surface it (most native Cocoa apps); the bundle-ID check is the permissive fallback for the AX-stubborn tail. Composes options 1/3: AX probe failure never itself blocks paste; pill focus-steal is still caught because BOTH would fail. This is effectively Option 3 with the AX probe kept as opportunistic telemetry, not a gate.
- **Option 6 — per-app allowlist.** User-maintained list of bundle IDs to always paste into. High friction, not worth considering for a solo-dogfood product.

## Option 3 regression risk — detailed audit

Paths that could make Ninimma `NSWorkspace.frontmostApplication` during the ~100ms paste window:

- **Hotkey release path.** No window activation on release — `CGHotkeyEventTap` posts events without ever touching `NSApp.activate`. Grep `NSApp.activate\|makeKeyAndOrderFront` across Sources returned only `UnifiedWindowController.swift:150-151`, which is not on this path. **Safe.**
- **Pill-click stop path.** `DraggablePanel` returns `canBecomeKey = false` + `canBecomeMain = false` (`PillOverlayPresenter.swift:78-84`) and the panel uses `.nonactivatingPanel` (`:247`). Regression-guarded by `PillOverlayPresenterTests.swift:425-466`. **Safe.**
- **Menu-bar status-item Stop click (MV-NAP-3).** `NSStatusItem`'s menu is owned by the system menu-bar process, not by Ninimma; selecting a menu item fires `handleRecordButtonTap` (`StatusItemController.swift:133-135`) without activating Ninimma. macOS does not promote a menu-bar-only owner to frontmost when its status menu is used. MV-NAP-3 has not been runtime-verified per `ManualPillOverlayVerification.md:190-193`. **Likely safe, unverified.**
- **Escape / cancel paths.** No activation in `PillOverlayPresenter.hide()` (`:533-543`); cancellation routes through the view model. **Safe.**
- **Settings window open during recording.** `UnifiedWindowController.showWindow` explicitly does `window.makeKeyAndOrderFront(nil); NSApplication.shared.activate(ignoringOtherApps: true)` (`UnifiedWindowController.swift:150-151`). Called only from explicit menu actions (`PersonalScribeAppMain.swift:208-214`) — the user has to pick a menu item. If they do this mid-recording and the transcript finishes while Settings is frontmost, Option 3 would return clipboard-only. **Regressed, narrow.**
- **App-switcher (Cmd-Tab).** If the user Cmd-Tabs to Ninimma while a transcript is landing, frontmost is Ninimma and Option 3 returns clipboard-only. Same pre-2026-04-20 behavior — not a new regression. **Same as pre-regression baseline.**

Net: Option 3 reintroduces exactly two narrow regressions (user Cmd-Tabs to Ninimma; user opens Settings mid-recording). Both are user-induced mid-flight activations, not passive UX flicker.

## Recommended option

**Option 5 (AX-probe OR bundle-ID)** — confidence **medium**. Paste when `focusedElementHasCursor() || frontmostBundleID != self.bundleID`. Fixes Sublime / VS Code / Electron (bundle-ID permissive for them), preserves the #003 safety net at the panel level (covered by tests), keeps the probe as an opportunistic confirmation for native Cocoa apps, and avoids the Cmd-Tab-during-paste / Settings-open-during-paste narrow regressions that pure Option 3 brings back. If we are unwilling to compose the two signals, Option 3 is the next-best simple fix given the #003 panel contract is test-guarded.

## Implementation shape

- **Files to change:** `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift` (change `deliverBatch` guard at `:113-116` to `OR` the probe with a bundle-ID check; retain the probe dependency for tests); no changes to `PasteRouting.swift`.
- **Approx LOC delta:** +4 / −0 in `deliverBatch`; delete the `// MARK: - Rollback fallback` block (`:132-165`) since we no longer need the reversion template.
- **Tests to update / update:** `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift` — update `testDeliverBatchSkipsPasteWhenFocusedElementHasNoCursor_ReturnsClipboardOnly` (`:318-349`) to also set frontmost = self bundle ID (otherwise the new OR makes it paste); add one new test "pastes when AX probe fails but frontmost is another app"; `testDeliverBatchPastesWhenFrontmostIsSelfButFocusedElementHasCursor` (`:115-142`) stays green; `testDeliverBatchAlwaysWritesToClipboardEvenWhenPasteSkipped` (`:351-376`) needs frontmost=self too. Add manual-verification entry MV-AX-042 in `ManualPillOverlayVerification.md` covering Sublime + VS Code paste.
- **Behavior change summary:** paste now fires for any focused target outside Ninimma's bundle, even when AX attributes/roles are unrecognized. Clipboard-only card still appears when (clipboard-only mode) OR (AX not granted) OR (AX probe fails AND frontmost is Ninimma).

## Open questions / remaining unknowns

- MV-NAP-3 (menu-bar stop) is not runtime-verified — the panel contract covers pill clicks but the status-item path is inferred safe, not observed.
- VS Code behavior unconfirmed in the repo; inference from Electron AX shape only.
- `AXIsProcessTrusted()` caches in some macOS builds — not load-bearing for #042 but worth noting that the AX probe will return false on first post-grant call until process restart, which compounds the current symptom.
