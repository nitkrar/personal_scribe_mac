# Issue 6 — Pill panel should not steal focus on click

**Status**: Open, pending investigation
**Raised**: 2026-04-21 session (during Issue 1 post-mortem)

## Symptom (from user report)

Clicking the pill or a menu item to stop a recording causes `NSWorkspace.frontmostApplication.bundleIdentifier` to return Ninimma's bundle ID rather than the previously-focused app (Slack, VS Code, etc.). This broke the legacy `resolveTarget()` paste path — the app treated itself as the target and skipped auto-paste.

Issue 1 (`08ce3fc`) shipped a workaround: query the AX system-wide focused element and paste only if it has a cursor. That is reactive — paste succeeds when the focused-element AX query happens to come back to the previously-focused app before it shifts. If the user clicks the pill hard enough / fast enough that macOS fully transfers focus, the AX probe correctly returns "no cursor" and paste is skipped. Correct behaviour, but still pastes-skipped-when-it-shouldn't-have-been.

## Proper fix (from Wispr Flow reverse-engineering — agent report 2026-04-21)

Make the pill panel non-activating at the AppKit level:
- `NSPanel` with `styleMask` containing `.nonactivatingPanel`
- `becomesKey` returns `false` unless the panel genuinely needs keyboard input
- `canBecomeKey` / `canBecomeMain` override to `false`
- SwiftUI's `.windowStyle(.hiddenTitleBar)` + `setIgnoreMouseEvents(_:forward:)` pattern if applicable
- Click events delivered to the pill without `NSApplication.activate`

Wispr Flow's Electron equivalent: `type: "panel"`, `focusable: false`, `skipTaskbar: true`, `alwaysOnTop: true`, `setIgnoreMouseEvents(true, {forward:true})`. Result: clicking the pill never promotes the app to frontmost, so Cmd+V after transcription lands in the previously-focused target app.

## Investigation steps

1. Find our pill panel class (likely in `Sources/PersonalScribeAppKit/Overlay/` — `PillOverlayPanel` or similar).
2. Read its `styleMask`, `becomesKeyOnlyIfNeeded`, `canBecomeKey`, `acceptsMouseMovedEvents`.
3. Compare against `ResponseCard.swift:75` which already uses `.nonactivatingPanel` correctly.
4. Verify the click target handler (`onTap: { Task { await coordinator.toggle() } }` in `PersonalScribeAppMain.swift:107`) does not call `NSApp.activate(ignoringOtherApps:)` or equivalent focus-stealing API.
5. TDD where possible (panel style-mask assertion); manual verification for the behavioural "click doesn't change frontmost" check — add to `ManualPillOverlayVerification.md`.

## Acceptance

After the fix, with Ninimma running and a recording in progress:
- User clicks the pill to stop
- `NSWorkspace.shared.frontmostApplication` still returns the pre-click app (Slack/VS Code/etc.)
- Transcription completes, auto-paste lands in the pre-click app (no clipboard-only-notice card)

The Issue 1 AX probe remains as belt-and-suspenders.
