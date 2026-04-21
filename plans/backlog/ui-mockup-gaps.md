# UI Mockup Gaps — Remaining Divergences from Manus Bundle

Open as of 2026-04-20. Findings from parallel Claude + Codex review rounds against `plans/App UI design/Claude_Final_Bundle_Prompt.md` + mockup PNGs. The parallel M-series session has closed menu bar (M5) and core startup wiring; the items below sit in tabs / components that haven't been addressed yet.

Scope excludes the floating pill overlay (separate workstream).

## Status of reviewed areas

| Area | State |
|------|-------|
| Menu bar | ✅ Fixed in M5.1/M5.2 (layout, icons, Paste, Mic submenu, Check for Updates, SF Symbols via `iconName`) |
| Unified window shell | ✅ On-spec; only gap is hard-coded "Microphone" footer (tracked below) |
| Startup / lifecycle | ✅ `startupCoordinator.start()` now called (`e3eec52`); legacy controllers deleted |
| Modes — write path + live refresh | ✅ Fixed (`09d7612`): `Set Active` button + `activeModeStream` subscription |
| App bundle size regression | ✅ Fixed (`561e157`): release binary stripped; 20MB → 9.5MB |

## Home tab

- [x] **Empty state missing** — mockup shows centered feather + "No transcriptions yet" + "Press ⌥⌥ to start recording" when `recent` is empty. Current view renders nothing under the section header. → `1d4fcef` (mockup-gaps B.1). NB: hotkey hint sourced from `HotkeyPreference` via `HotkeyShortcutFormatter.displayString`, not hardcoded.
- [x] Section label "Recent" should read "RECENT TRANSCRIPTIONS" (mockup text). → `b05609e` (mockup-gaps B.2).
- [x] Card 3 label reads "Minutes saved" — mockup uses "Mins saved" verbatim. → `d3639b4` (mockup-gaps B.3).
- [x] WPM avg forces `.0` formatting; mockup shows integer at zero. → `776aa7c` (mockup-gaps B.4).

## Transcriptions tab

- [x] **Row renders `entry.text` as both title AND preview** — same text drawn twice in one row. Tab passes `title: entry.text, preview: entry.text` to `TranscriptRow`. Pick one surface and drop the other. → `050d46b` (mockup-gaps A.1). `TranscriptRow` gained a `DisplayStyle` enum with a `.detail` variant that drops the title slot; Home-tab callers stay on `.summary` default.
- [x] Date grouping emits `APRIL 17, 2026` (`MMMM d, yyyy` uppercased); mockup uses compact `APR 18`. → `7f42970` (mockup-gaps A.2).
- [x] Row height not constrained to `PersonalScribeTheme.RowHeight.tall` (56). → `5d75d40` (mockup-gaps A.3).
- [ ] Mockup shows a mode pill ("Dictation Mode" / "Command Mode") on each row's trailing edge. Not present. **Deferred** — requires schema change to `TranscriptEntry`; scope captured in `plans/backlog/transcript-trigger-context.md` (park until Command Mode lands).
- [x] Mockup timestamps are wall-clock (`2:34 PM`); code uses relative (`5m ago`). → `0bb8084` (mockup-gaps A.4) + `e9c9481` (NBSP test fix).
- [x] No `WindowTint.primaryBackground` on the tab root — inherits from ancestor. → `7d460cf` (mockup-gaps A.5).

## Permissions sub-tab

Logic is solid (order, dot colours, live refresh, correct deep-links). Visual chrome still off:

- [x] **Rows rendered as flat HStacks** — mockup shows rounded white card per row with subtle elevation. → `529d399` (mockup-gaps C.2).
- [x] **"Grant Access" is a plain text button** tinted `Status.link`. Mockup shows a filled blue pill button with white text. → `6ddd612` (mockup-gaps C.3). Hand-rolled `Capsule()` button since `ActionButton.primary` fills with champagne, not blue.
- [x] **"Required" text label missing** beside the orange dot. Mockup shows the literal word "Required". → `e6fc482` (mockup-gaps C.4) + `69566d1` (C.5 "Granted" label counterpart).
- [x] **"REQUIRED PERMISSIONS" section header missing** above the row stack. → `2bbf57b` (mockup-gaps C.1).
- [x] Row subtitle copy diverges from mockup ("Capture audio for transcription." vs "Required for voice recording"). → `24cc9f8` (mockup-gaps C.6) + `d5b6379` (C.7 Input Monitoring subtitle sourced from `HotkeyPreference`).

## Settings → General

- [x] **"Style" picker (Classic / Mini / None) with LIVE SwiftUI pill previews is entirely missing.** Mockup centerpiece. Must read `@EnvironmentObject var pillAppearance` and render bg `#1A1B2E` (dark) / `#F0EDE8` (light). NOT static images. → `5f86055` (mockup-gaps D.1). NB: wired via `GeneralTabViewModel.pillAppearance` rather than a separate `@EnvironmentObject` — the project uses the VM pattern for General-tab state.
- [x] **APPLICATION section missing** — "Launch at login" and "Show in Dock" toggles. → `18223ba` (mockup-gaps D.2).
- [x] **TEXT INPUT section missing** — "Paste result text" master toggle. → `b5f033f` (mockup-gaps D.3).
- [ ] Mic device indicator in the title-bar accessory (mockup: "MacBook Pro Microphone (Default)") — not implemented. **Deferred** — see follow-ups below.

### Deferred follow-ups (recorded during mockup-gaps D landing, 2026-04-21)

- [ ] Mic device title-bar accessory (unified-window chrome) — overlaps with parallel session's `AudioInputDeviceProviding` wiring for bug #18. Revisit once that lands.
- [ ] Wire `PillStyle` preference to `PillOverlayView` runtime rendering. D added the preference + Settings UI; the overlay still always renders the Classic visuals. When Mini: smaller compact pill. When None: overlay hidden regardless of `PillVisibilityMode`. Requires reconciling with `PillVisibilityMode` semantics.
- [ ] Wire `pasteEnabled` master toggle to `OutputService` (or equivalent). When disabled, no paste + no clipboard write. D added the preference + UI; downstream service is unchanged.

## Unified window shell

- [ ] Sidebar mic footer hard-codes `Text("Microphone")` (inline comment admits it's an M3.1 placeholder). Should consume `AudioInputDeviceProviding` to show the current device.
- [ ] `AppTab.transcriptions.systemImageName` = `text.alignleft`; mockup glyph is a waveform.

## Theme tokens — semantic duplicates

Not blocking; worth consolidating during a cleanup pass:

- [ ] `Radius.pill = 12` coexists with `Radius.capsule = 100`. Reference `SeshatTheme.swift` used a single `Radius.pill = 100`. Risk: a caller writing `Radius.pill` expecting a capsule gets 12pt rounded-rect. Rename `Radius.pill` → `Radius.pillLegacy` or drop if unused.
- [ ] `Palette.pillStopRed = #EF5350` duplicates `Pill.Dark.stop / Pill.Light.stop = #F75138`. Pick one.
- [ ] `Palette.brandChampagne` (`#D4D0C8 / #6B6760`) and `Accent.champagne` (`#CCB990`) are two different "champagne" values.
- [ ] `Palette.statusReady/statusRecording/statusLink` parallel `Status.success/error/link`. The palette-adapted set is **intentional** (project policy, codified in `StatusPillTests`) — the duplication is the gap, not the color choice.
- [ ] `Typography.display` (20/bold) duplicates `Typography.title` (20/bold).

## Palette bundle — product decisions still open

The Manus bundle doesn't enumerate:

- [ ] What `WindowTint.warm` / `.neutral` render in system **dark** mode. Bundle's own `SeshatTheme.swift:217` tail comment claims `#0E0E14 / #111318` dark fallback, but the enum body returns the single light hex unconditionally. Self-contradictory. Code mirrors the enum.
- [ ] `PillAppearance.system` token selector. Bundle only returns `nil` from `nsAppearance`. Code invented `effectiveIsDark(systemIsDark:)` to bridge — ratify or revise.
- [ ] Legitimacy of dark tint + light pill combination (unusual; permissible by independence invariant but not mocked).
- [ ] Which wins: `Palette.for(scheme:)` (scheme-driven) vs `WindowTint.primaryBackground` (user-selection-driven). Two parallel paths, bundle defines only one.

## Not acting on

These were reviewer flags against a stale reference (`SeshatTheme.swift` drop-in) that the project deliberately diverged from. Tests codify the current policy — do NOT "fix" without explicit user reversal:

- UserDefaults keys using `Seshat*` prefix. Project policy: strip prefix (see `PreferenceMigrator.swift`, `WindowTintTests.testUserDefaultsKeyHasNoSeshatOrPersonalScribePrefix`).
- `StatusPill.Status.ready` using `palette.statusReady` instead of `Status.success`. Project policy: palette-adaptive green (see `StatusPillTests.testStatusColorForReadyUsesThemeStatusReady`).
