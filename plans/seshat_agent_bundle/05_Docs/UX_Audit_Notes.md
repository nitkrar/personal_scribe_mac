# Seshat UX Audit — Findings

## 1. App Architecture Overview
Seshat is a macOS menu-bar dictation app (Apple Silicon, macOS 14+). It uses:
- **FluidAudio / Parakeet-TDT 0.6B v2** for local speech-to-text
- **SwiftUI + AppKit** for UI
- A floating **pill overlay** (bottom-center of screen) for recording state
- A **MenuBarExtra** popover for controls

Current UI surfaces:
1. Menu bar icon (SF Symbol "mic" / "mic.fill" / "mic.slash")
2. MenuBarExtra popover (plain SwiftUI menu items — text + buttons)
3. Floating pill overlay (recording/transcribing state indicator)

---

## 2. Identified UX Bugs & Pain Points

### BUG-01: App Unresponsive at Start (Critical)
**Source:** User report + code analysis
**Root cause:** On first launch, the model download begins immediately (Parakeet ~66MB + CoreML models). The `PillOverlayViewModel` starts in `.idle` state, but the `MenuBarSceneModel` does not block or indicate "not ready" until the download completes. The `Record` button is rendered and clickable but the coordinator is not ready to handle a tap — the session will silently fail or hang.
**Additional factor:** `GlobalHotkeyMonitor` uses `NSEvent.addGlobalMonitorForEvents` which silently returns nil until Input Monitoring permission is granted — no feedback to user.
**Fix:** Show a "Preparing…" / download state in the popover with the button disabled. Only enable Record once model is ready.

### BUG-02: Clicks Don't Work / Pill Overlay Not Receiving Taps (High)
**Source:** User report + `PillOverlayPresenter` code
**Root cause:** The `DraggablePanel` uses `.nonactivatingPanel` style mask and `ignoresMouseEvents = false`, but the `ClickThroughHostingView` overrides `acceptsFirstMouse` to return `true`. The issue is that `canBecomeKey = true` on the panel but the SwiftUI `onTapGesture` inside a non-key, non-main window can fail to fire in certain macOS versions (14.x). Additionally, the panel `level = .floating` can place it behind the menu bar popover in some configurations.
**Fix:** Use `NSPanel` with explicit mouse event routing; add a dedicated `NSButton` overlay or use `NSClickGestureRecognizer` instead of SwiftUI `onTapGesture` for the pill.

### BUG-03: No Visual Feedback for Permission States (High)
**Source:** `MenuBarScene.swift`
**Current behavior:** When mic is denied, the menu shows "Open System Settings" but the icon just shows `mic.slash` with no explanation. When not-yet-requested, it shows "Grant microphone access" with no context.
**Fix:** Show an inline banner/callout in the popover explaining WHY permission is needed, with a clear CTA.

### BUG-04: MenuBarScene is Plain Text Menu — No Visual Hierarchy (High)
**Source:** `MenuBarScene.swift`
**Current behavior:** The popover is just `Text("Seshat — Idle")` + raw `Button` items. No icons, no spacing, no visual grouping. Looks like a debug menu.
**Fix (confirmed architecture):** Replace `MenuBarExtra` popover with a native `NSMenu`. Menu items: active Mode name (non-interactive header), Start/Stop Recording `⌥⌘`, History, Settings, Quit. No SwiftUI components, no state display, no transcript preview. The Pill is the sole live UI surface. See `03_Surfaces/MenuBarMenu/IMPORTANT.md` for the full spec.

### BUG-05: Record Button State Mismatch During Transcribing (Medium)
**Source:** `RecordButtonViewModel.swift`
**Current behavior:** During transcribing, the button title is "Transcribing…" and `isEnabled = false`. But the menu item still renders as a clickable button — just does nothing. No visual disabled state in `MenuBarScene`.
**Fix:** Visually disable/grey out the button and show a spinner inline.

### BUG-06: Transcript Only Visible in Popover Until Replaced (Medium)
**Source:** Manual verification doc
**Current behavior:** "No notes database. Transcript is visible only in the popover until replaced." — each new transcription overwrites the previous one with no history.
**Fix (confirmed architecture):** Implement `TranscriptStore` as a persistent `[TranscriptEntry]` array (SQLite or JSON on disk). All transcripts are auto-ingested into the `NotesWindow` — the personal knowledge base. The menu bar popover shows nothing. History is accessed via the History menu item, which opens `NotesWindow`. See `03_Surfaces/NotesWindow/notes_surface.png` for the full design reference.

### BUG-07: Clipboard Clobber on Copy (Medium)
**Source:** `PasteInjector.swift`, manual verification doc
**Current behavior:** Clipboard is saved/restored but with a 250ms window — race condition with clipboard managers (Maccy, Raycast). The `restoreDelay` of 0.25s is too short for slow apps.
**Fix:** Increase restore delay to 0.5s; add user-configurable delay in settings.

### BUG-08: No Onboarding / First-Run Experience (High)
**Source:** Code + manual verification
**Current behavior:** App launches directly into the menu bar. No welcome screen, no explanation of what the app does, no guided permission flow. User must know to click the mic icon.
**Fix:** First-launch onboarding sheet/window with step-by-step permission grants.

### BUG-09: Hotkey Requires Input Monitoring Permission — Silently Fails (Medium)
**Source:** `GlobalHotkeyMonitor.swift`
**Current behavior:** `NSEvent.addGlobalMonitorForEvents` silently returns nil if Input Monitoring isn't granted. No feedback to user. Double-tap ⌥⌥ does nothing.
**Fix:** Detect permission state and show inline prompt in settings/popover.

### BUG-10: Pill Overlay Always Visible (Idle Dot) — No Way to Hide (Low)
**Source:** `PillOverlayViewModel` — `.idle` state shows a dot
**Current behavior:** A small grey dot persists at the bottom of the screen even when not recording. Some users may find this intrusive.
**Fix (confirmed architecture):** Implement the three-mode pill visibility system in `AppState`:
- **Always On** — pill is always visible; idle state is a compact minimal bar
- **Auto-show** — pill is hidden at rest; slides in when recording starts, fades out after transcription completes
- **Hidden** — pill never shows; user relies on menu bar + hotkeys only
This is a user-configurable setting in `SettingsWindow`. Default is Auto-show. See `03_Surfaces/PillOverlayWindow/architecture.png` for the full three-mode reference.

---

## 3. Design Gaps (UX Polish)

### GAP-01: No App Icon / Logo
The app uses a generic SF Symbol "mic" as its only visual identity. No custom icon, no brand.

### GAP-02: No Settings Panel
No way to configure: model selection, hotkey, auto-paste toggle, language, theme.

### GAP-03: No Multi-Model AI Support UI
The backlog mentions llama.cpp + Apple Foundation Models for future AI features. There is no UI scaffolding for model selection, AI mode switching, or model download management.

### GAP-04: No Transcript History
Each transcription replaces the last. No searchable history, no export.

### GAP-05: No Dark/Light Mode Awareness
The pill overlay uses `.regularMaterial` which adapts, but the popover has no explicit dark mode styling.

### GAP-06: Accessibility
No VoiceOver labels on pill overlay elements. No keyboard navigation in popover beyond shortcuts.

---

## 4. Redesign Priorities

| Priority | Item |
|---|---|
| P0 | Fix unresponsive start (disable Record until model ready) |
| P0 | Fix pill overlay tap not working |
| P1 | Implement native NSMenu with mode header and action items (see `03_Surfaces/MenuBarMenu/IMPORTANT.md`) |
| P1 | First-run onboarding flow |
| P1 | New logo / app icon |
| P2 | Settings panel (model, hotkey, auto-paste) |
| P2 | Multi-model AI support UI |
| P2 | Transcript history panel |
| P3 | Accessibility improvements |
| P3 | Idle dot hide toggle |
