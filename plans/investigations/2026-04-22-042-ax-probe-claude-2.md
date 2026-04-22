# #042 AX probe review — Claude second pass (2026-04-22)

## Root cause confirmation

The probe at `ClipboardBatchOutput.swift:220-259` queries `kAXFocusedUIElementAttribute` on the system-wide element (`:221-227`), then returns `true` only if the focused element exposes `kAXInsertionPointLineNumberAttribute` (`:234`), `kAXSelectedTextAttribute` (`:237`), or has role in {`kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`} (`:248-256`). Sublime Text draws its editor buffer in a custom NSView (no `NSTextView` inheritance), so its focused element typically reports role `AXGroup` or `AXUnknown` and exposes neither insertion-point nor selected-text as *readable* attributes. `attributeIsReadable` (`:261-268`) requires `status == .success && value != nil` — both fail for non-text surfaces. Probe returns `false`, `deliverBatch` hits the guard at `:113-116`, returns `.clipboardOnly`, and `MenuBarSceneModel.swift:154` fires the "Copied to clipboard" card. Matches the reproduction. Note `kAXValueAttribute` is widely readable but NOT a reliable cursor signal — `AXStaticText`, `AXButton`, sliders all expose it.

## Option 1 — PID inequality

- **Mechanism:** after `AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute, &focusedRef)` succeeds, call `AXUIElementGetPid(focused, &pid)` (C function in `HIServices.framework/.../AXUIElement.h`, works on any AXUIElementRef). Paste when `pid != getpid()`.
- **Pros:** One-line fix. Keeps AX-layer defense: any future regression where Ninimma steals AX focus still skips paste. Fixes Sublime, VS Code, Electron, and any AX-stubborn app in one stroke.
- **Cons:** False-positives when focused element in a third-party app is non-text — Finder sidebar row (`AXOutline`), Safari link focused via Tab, System Settings toggle. In Finder the worst case is Cmd-V binds to "paste item", which could paste a filename-interpretation of the transcript. Low-severity but real. Clipboard still holds the transcript either way, no data loss.
- **Feasibility: high** — additive; mockable via existing `FocusedElementCursorProbe` seam.

## Option 2 — extended roles

- **Mechanism:** accept `kAXGroupRole`, `kAXUnknownRole`, `kAXWebAreaRole` in addition to current three, conditionally on `pid != getpid()`.
- **Pros:** Targets the symptomatic role set (Sublime → `AXGroup`/`AXUnknown`, Chrome/Safari web forms → `AXWebArea`).
- **Cons:** `AXGroup` is the most-used container role in macOS — toolbars, popovers, sidebars, any `NSView` subclass that opts into AX. Focused `AXGroup` is more likely to be UI chrome than a text surface. `AXUnknown` even less specific. Trades a false-negative for a broad false-positive; semantically dishonest — if we're going to accept "anything outside Ninimma", Option 1 states that contract honestly.
- **Feasibility: medium** — code-simple but the role-→-cursor contract is wrong.

## Option 3 — revert to bundle-ID

- **Mechanism:** delete the `focusedElementHasCursor` guard (`:113-116`); restore the commented `resolveTarget()` block (`:154-165`); gate paste on `target == .frontmostApp`.
- **Pros:** Verbatim pre-2026-04-20 behavior, known-working for Sublime/VS Code/TextEdit/iTerm. Simplest diff. No AX probe to maintain.
- **Cons:** Loses AX-layer defense. #003 is fixed at the panel level *today*, but any new code path that activates Ninimma during the paste window silently regresses. Bundle-ID check also allows pasting into Ninimma itself (Settings window open with a text field focused while recording → transcript would paste into our own settings field).
- **Feasibility: high** — mechanical revert, but strictly weaker than Option 1.

## Alternative options

**Option 4 — bundle-ID primary + PID-inequality rescue.** Primary gate: `frontmost.bundleID != selfBundleID`. If bundle-ID flags self, fall through to AX-focused PID check. Hot path is the cheap bundle-ID call; PID check is the rescue for the rare "Ninimma briefly frontmost but user's real cursor is elsewhere" case. More code than Option 1, but cleanly separates the common case from the defense. For Sublime specifically Option 4 resolves at the bundle-ID stage (Sublime IS frontmost) and the AX branch never runs.

**Option 5 — AXSetAttributeValue on `AXSelectedText`.** Bypass clipboard entirely. Rejected: fails on exactly the apps (Sublime/Electron/web views) where we need it; `REVIEW.md:137` flags this.

**Per-app allowlist / parent-chain walk / `AXValueAttribute`:** rejected — maintenance cost, cost-per-call, or false-positive on read-only text.

## Option 3 regression risk — detailed audit

Paths that could make Ninimma bundle-ID-frontmost during the ~100ms paste window (between `deliverBatch` call and `postPasteShortcut` CGEvent delivery):

- **Hotkey release** — global event monitor; no activation. **Safe.**
- **Pill click (Stop during recording)** — `DraggablePanel` has `canBecomeKey = false` + `canBecomeMain = false` + `.nonactivatingPanel` (`PillOverlayPresenter.swift:78-84, :247`). Click consumed by `ClickThroughHostingView` without activation. **Safe.**
- **Menu-bar status-item Stop click** — `NSStatusItem` click opens attached NSMenu (`StatusItemController.swift:100`). Standard AppKit: status-item menu tracking does NOT call `NSApplication.activate`, `NSWorkspace.frontmostApplication` does not change. No explicit test covering this and MV-NAP-3 runbook still open per ticket. **Unknown → likely safe but unverified.**
- **Escape / cancel** — `EscapeKeyMonitor` is a global monitor, no activation. Cancel short-circuits before `deliverBatch`. **Safe.**
- **Settings window open during recording** — `UnifiedWindowController.showWindow` calls `NSApplication.shared.activate(ignoringOtherApps: true)` at `:151`. If user opens settings while recording, Ninimma is bundle-ID-frontmost. With Option 3 we'd skip paste — arguably correct (user is now in Ninimma, shouldn't paste into old target). **Behavior change, debatable regression.**
- **Dock-icon mode (`.regular` activation policy)** — `ShowInDockPreference` users may spend time with Ninimma bundle-ID-frontmost. Under Option 3 those users lose auto-paste in that state. **Regressed under Option 3.**
- **Cmd-Tab during recording** — user-driven; if they switch to Ninimma they don't want paste back into prior app. **Safe / correct.**

Option 3 is *mostly* safe given the current #003 fix, with one unverified path (status-item menu tracking) and two latent hazards (future `NSApp.activate` callers; Dock-icon-mode users).

## Recommended option

**Option 1 (PID inequality)** — confidence: **medium-high**. Smallest code delta that keeps the AX-layer defense intact, fixes every AX-stubborn app in one stroke, and is testable via the existing `FocusedElementCursorProbe` seam. The Finder-sidebar false-positive is mild and non-destructive. If the team wants belt-and-suspenders, Option 4 (bundle-ID + PID fallback) is the runner-up.

## Implementation shape

- **Files to change:**
  - `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift` — replace `liveFocusedElementHasCursor` body with PID-inequality check. Keep `focusedElementHasCursor` closure seam (rename doc-comment concept to "focused element is in another app" but keep the type alias for test compatibility). Update rollback comment at `:132-165` to reflect new fallback direction.
- **Approx LOC delta:** −25 / +10 net. Remove the two `attributeIsReadable` calls, the role switch, and the helper (now unused); add `AXUIElementGetPid` + `getpid()` comparison.
- **Tests to update / add:**
  - `Tests/PersonalScribeAppKitTests/Output/ClipboardBatchOutputTests.swift` — existing 15 tests all use the injected closure and stay green untouched. Semantic rename of stub values only (`focusedElementHasCursor: { true }` now means "focus is in another app"); consider renaming test method names for clarity but not required.
  - Add a thin live-probe test that exercises `liveFocusedElementHasCursor` via an internal variant accepting an injected pid-of-focused-element closure. Three cases: focus-is-self / focus-is-other / focused-element-nil. ~40 LOC.
- **Behavior change summary:** paste fires whenever Accessibility is granted, clipboard-only mode is off, AND AX focused element's owning pid ≠ Ninimma's pid. #003 defense preserved (self-focus still skips). Sublime / VS Code / Electron / Chrome all paste. False-positive on non-text focus in other apps triggers a harmless ⌘V.

## Open questions / remaining unknowns

- Does `AXUIElementGetPid` return Ninimma's pid in any normal flow given the current `canBecomeKey = false` contract? Worth a runtime check — if AX focus never lands on us in practice, the PID defense is moot and Option 3 becomes more attractive.
- Status-item menu-tracking interaction with paste window: no explicit test; MV-NAP-3 runbook still open.
- Finder `AXOutline` Cmd-V side-effect if user fires recording while Finder sidebar is focused — dogfood edge, surface in manual verification.

---

## Agreement / divergence with prior pass

Note: the file at this path already contained a prior second-pass draft before I wrote this one; I formed my conclusions independently first, then read it. Prior pass file: `plans/investigations/2026-04-22-042-ax-probe-claude.md` (original).

- **Agree:** root cause (Sublime → `AXGroup`/`AXUnknown`, Chrome → `AXWebArea`); Option 2's `AXGroup` false-positive is fatal; Option 1 as baseline recommendation; Option 4 hybrid as the cleaner alternative.
- **New in this pass:** Dock-icon-mode (`.regular`) regression for Option 3 — prior pass focused on transient activation paths but didn't call out that `ShowInDock = true` users are *continuously* bundle-ID-frontmost whenever the main window has focus. That's a standing (not transient) Option 3 regression.
- **New in this pass:** `ResponseCard.swift:236` exposes `canBecomeKey: true` — not a #042 path (card appears post-paste-decision) but a latent #003-adjacent risk worth recording if Command Mode (Phase 4) ever activates the card during the paste window.
- **New in this pass:** reproduced the exact `attributeIsReadable` failure semantics (`status == .success && value != nil`, `:267`) — confirms why Sublime's `AXGroup` fails both attribute probes even if the framework returns `.success` with a nil ref.
- **Divergence on LOC estimate:** prior pass's −25/+10 matches mine. No disagreement on shape.
