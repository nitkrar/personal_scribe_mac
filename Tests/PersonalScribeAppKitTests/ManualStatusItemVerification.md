# Status Item — Manual Verification Runbook

The `NSStatusItem` icon loads from the SwiftPM resource bundle
(`Bundle.module`) at runtime — a path the unit tests exercise but
cannot fully prove for a packaged `.app` build. Tick each box the
first time you dogfood a change that touches `StatusItemController`
or `StatusItemIconLoader`.

---

## Baseline icon

- [ ] **MV-SI-1** Launch the packaged `.app` (via `scripts/package.sh -ir`
  or DMG install). The menu-bar status item shows the **quill glyph**,
  not the text letter "S". Regression guard for the
  `NSImage(named:) -> nil` bug fixed by loading through `Bundle.module`.
- [ ] **MV-SI-2** Flip macOS Appearance between Light and Dark. The
  icon re-tints appropriately (template-rendering-intent honoured from
  the asset catalog `Contents.json`).

## Tint under session state

- [ ] **MV-SI-3** Start recording — the icon tints red.
- [ ] **MV-SI-4** Stop recording; while transcribing the icon tints orange.
- [ ] **MV-SI-5** When idle again, the icon returns to the default
  monochrome template tint.

## Brand copy and accessibility

- [ ] **MV-SI-6** Open the status-item menu and confirm the quit row reads
  `Quit <AppBrand.displayName>`.
- [ ] **MV-SI-7** Hover the status item and inspect it with Accessibility
  Inspector or VoiceOver. Confirm the tooltip/accessibility label uses the
  current app name in all three states: `<AppBrand.displayName>` at idle,
  `<AppBrand.displayName> — recording` while recording, and
  `<AppBrand.displayName> — transcribing` while transcribing.

## Menu-bar navigation routing

- [ ] **MV-SI-8** Open the unified window, click into **Settings → About**
  (or any non-Home tab), then close or background the window. Click the
  status-item menu → **Home**. The window raises showing the **Home**
  tab — not whatever tab was last active. Regression guard for the
  `openHome: showUnifiedWindow` bug where the menu item only raised the
  window without switching tabs.
- [ ] **MV-SI-9** With the unified window open on any tab, the left
  sidebar (Home / Transcriptions / Modes / Settings) is always visible.
  Clicking the sidebar toolbar chevron does NOT hide it. Resizing the
  window down to `windowMinWidth` (760pt) keeps the sidebar pinned —
  detail pane compresses, sidebar does not collapse. Regression guard
  for bug #1b (2026-04-21 dogfood) where About forced the sidebar to
  auto-collapse leaving the user stranded on the About view.

## Copy Last Transcript (bug #9)

- [ ] **MV-SI-10** With at least one transcript in history, open the status-item menu → **Copy Last Transcript**. Open any app (TextEdit / Notes) and press ⌘V — the most recent transcript pastes. Also check the pasteboard programmatically: `pbpaste` in Terminal prints the same text.
- [ ] **MV-SI-11** With an empty transcript history (fresh install), click **Copy Last Transcript**. The clipboard content is unchanged (verify `pbpaste` before and after). Regression guard: the action must not clear the clipboard when there's nothing to copy.
- [ ] **MV-SI-12** Title of the menu item reads **Copy Last Transcript**, not 'Paste Last Transcript'. Icon remains `doc.on.clipboard`.

## Menu-bar header + tab entries (bugs #6, #16)

- [ ] **MV-SI-13** With an active mode, open the status-item menu. The top header reads `<AppBrand.displayName> — <active mode>` on a single line (e.g. "Ninimma — Dictation") — NOT two stacked grey rows. With no active mode, the header reads just `<AppBrand.displayName>`. Regression guard for bug #6 (2026-04-21 dogfood) where the two-header layout wrapped as "Ninimma — dictation" across two lines.
- [ ] **MV-SI-14** With the unified window closed, click the status-item menu → **History**. The unified window opens pre-selected to the Transcriptions tab. Close it; click **Settings** — window opens on the Settings tab. Regression guard for bug #16.
- [ ] **MV-SI-15** Menu row order under the header: **Home** (house.fill) → **History** (waveform) → **Settings** (gearshape). Then a separator, then **Start Recording** / **Copy Last Transcript**, separator, and **Quit** terminates the menu. Submenu (Microphone) slots between the trailing separator and Quit when input devices are discoverable.
