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
