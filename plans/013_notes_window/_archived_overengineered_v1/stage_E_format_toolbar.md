# #013 Stage E — Format toolbar (B / I / list / link)

**Ticket:** #013 NotesWindow
**Stage:** E — minimal format toolbar below the editor
**Status:** planning (source-only plan; no code, no commits)

---

## 1. Goal

Add a four-button format toolbar to the NotesWindow editor so the user can toggle **bold**, **italic**, **bullet-list**, and **link** on the current selection / line, with standard macOS keyboard shortcuts. Delivers the minimum formatting surface implied by the mockup (`notes_surface.png` — the `B  I  ☰  🔗` icon row just above the `Ask Seshat…` button) and nothing more.

After Stage E ships, the user can DO:

- Select text → click **B** (or ⌘B) → selection becomes bold.
- Select text → click **I** (or ⌘I) → selection becomes italic.
- Place cursor on a line → click bullet icon (or ⌘⇧8) → line turns into a bulleted item; Enter continues the list; Enter on an empty bullet exits list mode.
- Select text → click link icon (or ⌘K) → popover with a URL field → selection becomes a hyperlink.

Explicitly **out of Stage E**: headings, numbered lists, code blocks, tables, images, colours, strikethrough, inline citations, LaTeX, export-to-PDF/DOCX, syntax highlighting, collaborative editing.

---

## 2. Storage-format decision

**Recommendation: Markdown string in the `body` TEXT column.** Stage E assumes Markdown. If Stage B picks AttributedString, this plan must re-open Section 2 & 5 as a coordinated B+E scope change (flag to user, do not silently adapt).

Rationale (Markdown wins):

- **Single table, single column.** #013 policy is "notes = transcripts". Transcripts today are plain UTF-8 text in a TEXT column; Markdown stays backward-compatible — an unformatted transcript IS valid Markdown. No migration, no split columns.
- **FTS5 (Stage C) stays simple.** FTS5 indexes the raw `body` TEXT column directly. Yes, `**bold**` syntax leaks into the index (see Stage C coupling in §8), but that's cheap to fix with a post-parse stripper feeding a shadow `body_plaintext` column **if** searches on bold markers become a real problem. AttributedString would force a derived plaintext column from day one.
- **Export is trivial.** Copy-as-markdown to Obsidian / Notion / Slack / GitHub-comments is the user's real workflow per UX-Audit §2 BUG-06 ("personal knowledge base"). RTF → markdown round-trip is lossy; markdown → markdown is identity.
- **Human-readable on disk.** Aligns with project precedent (JSONL for history pre-#026, plain transcripts today). User can grep / rescue / diff notes without opening the app.
- **AppKit rich editing is not free either way.** Even AttributedString would need an `NSViewRepresentable` wrapping `NSTextView` to get real ⌘B behaviour. With Markdown, the same bridge exists — we just translate `toggleBold:` into a `**…**` splice on the Swift side. The round-trip "loses fidelity" concern is moot because we never leave Markdown.

**Downsides acknowledged:**

- WYSIWYG rendering (bold shown bold while editing) is extra work — addressed in §5 under "render mode". Stage E ships with always-markers-visible (Obsidian / source-mode) to stay small; render-on-blur is a follow-up.
- FTS5 false-positives on `**bold**` hitting the query `bold` — see §8.

**Stage B coupling:** Stage B is the editor surface. If Stage B's plan commits to `AttributedString` for the editor's `body` property, Stage E must flip: use `NSTextView` toggles via `NSFontManager.addFontTrait(.boldFontMask)` etc., and Stage C gets a new derived plaintext column on its critical path. **Read `plans/013_notes_window/stage_B_editor_and_persist.md` before Stage E execution kicks off.** If Stage B is silent on storage format, Stage E's pick (Markdown) is the authoritative call and Stage B must align.

---

## 3. Toolbar design

**Placement:** Horizontal bar pinned to the bottom of the editor pane, above the `Ask Seshat…` button and below the editor's `ScrollView`. Aligned flush-left with the editor's left padding. Fixed 32pt height. Background = `Palette.surface`; 1pt top divider in `Palette.secondaryTextBase.opacity(0.15)`.

**Buttons (left-to-right):**

| # | Symbol | SF Symbol | Shortcut | Action |
|---|--------|-----------|----------|--------|
| 1 | Bold | `bold` | ⌘B | Toggle bold on selection |
| 2 | Italic | `italic` | ⌘I | Toggle italic on selection |
| 3 | Bulleted list | `list.bullet` | ⌘⇧8 | Toggle bullet on current line |
| 4 | Link | `link` | ⌘K | Open link popover for selection |

**Button styling:**

- `Button` with `.buttonStyle(.plain)` + custom hover state (follows `PillAppearance` hover pattern).
- 28×28pt tap target, 16pt glyph, 4pt gap between buttons.
- Foreground: `Palette.primaryTextBase.opacity(0.75)` at rest; `Palette.primaryTextBase` on hover; `Palette.brandChampagne` when the trait is **active at current selection** (e.g. selection is already bold → B glyph lights up).
- Use `Radius.sm` (6pt) corner on hover background.
- `Image(systemName:)` follows the project's existing pattern (see `Overlay/PillOverlayView.swift`, `Settings/GeneralTab.swift`).

**Enabled-state logic:**

- All four buttons **disabled** (opacity 0.35, no hover) when the editor does not have first-responder focus.
- Bold / Italic / Link **disabled** when selection is empty AND cursor is outside the editor. (With cursor *inside* the editor and empty selection, bold/italic/link are enabled — they insert a marker-with-caret per §4.)
- Bullet **always enabled** as long as the editor has focus (line-level operation, no selection required).
- Link popover closes on Esc or click-outside.

**Accessibility:**

- `.accessibilityLabel` on each button: "Bold", "Italic", "Bulleted list", "Insert link".
- `.help(…)` tooltip mirrors the label + shortcut (e.g. "Bold (⌘B)").
- VoiceOver announces toggle state via `.accessibilityAddTraits(.isSelected)` when active.

---

## 4. Formatting semantics (Markdown)

All operations mutate the editor's `body: String` via the Stage B view model. The toolbar NEVER touches storage directly — it calls `NotesEditorViewModel.applyBold()`, `.applyItalic()`, `.toggleBullet()`, `.insertLink(url:text:)` and the view model emits the updated `body` + new selection range.

### 4.1 Bold / Italic

- **Non-empty selection:**
  - If selection is NOT already wrapped by the marker → wrap: `"hello world"` + select `"world"` + bold → `"hello **world**"`; selection becomes `"**world**"` (or just `"world"` — decide in implementation; tests lock whichever).
  - If selection IS wrapped (inclusive OR the selection equals the inner text) → unwrap: `"**world**"` + bold → `"world"`.
- **Empty selection (caret inside editor):** insert `**` + `**` and place caret between — next-typed char is bold. (Same for italic with `*`.)
- Markers: **bold = `**…**`**, **italic = `*…*`**. We deliberately do NOT support `__` / `_` variants (pick one per trait; tests lock it).

### 4.2 Bullet list

- Per-line operation. The toolbar finds the line containing the caret (or the set of lines spanned by a multi-line selection).
- Toggle rule per line:
  - If line does NOT start with `- ` (after leading whitespace) → prepend `- `.
  - If line starts with `- ` → strip it.
- **Enter key interception** (only while cursor is on a bullet line):
  - Enter on non-empty bullet line → insert `\n- ` (continue list).
  - Enter on EMPTY bullet line (`- ` + caret) → strip the `- ` and insert a plain `\n` (exit list mode).
- List marker: `- ` (hyphen + space). Open question on `*` vs `•` — see §9.

### 4.3 Link

- Click link icon (or ⌘K) → `LinkPopover` anchored to the button:
  - Text field: "URL" (required).
  - Text field: "Link text" — pre-filled with the current selection; editable.
  - Primary button: **Insert**. Secondary: **Cancel**.
- On Insert:
  - Non-empty selection → replace selection with `[<linkText>](<url>)`.
  - Empty selection → insert `[<linkText or "link">](<url>)` at caret.
- URL validation: accept anything non-empty; if missing scheme and starts with `www.` or matches a hostname regex, prepend `https://`. No heavy validation — the user's knowledge base, not a web form.
- Esc in popover = Cancel.

---

## 5. Editor bridging

**Assumption:** Stage B delivers a SwiftUI `NotesEditorView` backed by `NotesEditorViewModel` exposing `@Published var body: String` and `@Published var selection: NSRange` (or Swift `Range<String.Index>`). Stage E adds `@Published var isEditorFocused: Bool` to the same view model (Stage B can own the property; Stage E consumes it).

**Bridging options:**

1. **Pure SwiftUI `TextEditor`.** Simplest, but selection + first-responder bindings are awkward pre-macOS 15. Acceptable if Stage B targets macOS 15+; otherwise insufficient for Stage E's selection-aware toggles.
2. **`NSViewRepresentable` wrapping `NSTextView` (recommended).** Full control over selection, first-responder, key handling, and Enter-interception for bullets. Precedent: `Overlay/VisualEffectBlur.swift` already does `NSViewRepresentable` in this project.

Stage E prefers option 2 and assumes Stage B will choose it as well. If Stage B picks `TextEditor`, Stage E still ships (shortcuts via `.keyboardShortcut`, selection-aware toggles via Stage B's exposed bindings) but degraded: the bullet Enter-interception becomes best-effort, and the "active-trait highlight" on B/I buttons may flicker with selection latency.

**Markdown render mode in Stage E:** **always-markers-visible (source mode).** The editor shows literal `**bold**`. Rendering-on-blur (Notion/Obsidian live-preview) is a follow-up stage, not Stage E. This keeps Stage E's scope to string splicing + selection math and avoids attributed-text layout work.

---

## 6. TDD test strategy

**XCTest-coverable (rigid TDD):**

- `FormatToolbarButtonStateTests` — given `isEditorFocused`, `selection`, `body`, assert each button's `isEnabled` and `isActive` flags.
- `MarkdownBoldFormatterTests` — parameterised: input body + selection range + toggle → output body + new selection.
  - `"hello world"` + range `"world"` + bold → `"hello **world**"`.
  - `"hello **world**"` + range `"world"` + bold → `"hello world"`.
  - Empty selection at index 5 of `"hello"` → `"hello****"` with caret at 7.
- `MarkdownItalicFormatterTests` — same shape, single-asterisk.
- `MarkdownBulletFormatterTests` — toggle, multi-line selection span, Enter-continue, Enter-on-empty-bullet-exits.
- `MarkdownLinkFormatterTests` — non-empty selection, empty selection, URL normalisation (`www.x.com` → `https://www.x.com`).
- `LinkPopoverViewModelTests` — validation, default link-text = selection, Insert emits correct `InsertLink` action.

**Manual-verification-only (flexible TDD):**

- `MV-NOTES-FMT-01` — ⌘B while typing (no selection) makes next keystrokes bold; ⌘B again un-bolds next keystrokes.
- `MV-NOTES-FMT-02` — Undo / Redo after each of bold / italic / bullet / link leaves body + selection in the expected state.
- `MV-NOTES-FMT-03` — Bullet Enter on empty bullet exits list mode (caret stays on a blank line, `- ` gone).
- `MV-NOTES-FMT-04` — Link popover opens anchored to the button; Esc cancels; Return in URL field inserts.
- `MV-NOTES-FMT-05` — Focus handoff: toolbar buttons grey out when focus leaves the editor (e.g. click in the sidebar).
- `MV-NOTES-FMT-06` — VoiceOver reads "Bold, button, selected" when caret is in a bold run; keyboard-only navigation (Tab) reaches each toolbar button.
- `MV-NOTES-FMT-07` — ⌘K doesn't collide with "Clear" (Terminal convention) because the editor is first responder; verify in a scratch note.

Runbook lives at `Tests/PersonalScribeAppKitTests/ManualNotesWindowVerification.md` (extend the file Stage B creates; if absent, Stage E creates it).

---

## 7. Commit shape

Target **5 commits**, all prefixed `#013 step 5.N:`:

1. `#013 step 5.1:` FormatToolbar view + SF Symbol buttons + enabled-state wiring (no actions yet; button taps are stubs). Tests: `FormatToolbarButtonStateTests`.
2. `#013 step 5.2:` Markdown bold + italic formatters + view model hooks + ⌘B / ⌘I shortcuts. Tests: `MarkdownBoldFormatterTests`, `MarkdownItalicFormatterTests`.
3. `#013 step 5.3:` Bullet-list formatter + Enter interception + ⌘⇧8 shortcut. Tests: `MarkdownBulletFormatterTests`.
4. `#013 step 5.4:` Link popover + URL normalisation + ⌘K shortcut. Tests: `MarkdownLinkFormatterTests`, `LinkPopoverViewModelTests`.
5. `#013 step 5.5:` Manual-verification runbook entries (`MV-NOTES-FMT-01..07`) + accessibility polish (labels, traits, tooltips).

If Stage B ships late and Stage E must stub the view model, add a prefatory `#013 step 5.0:` with a minimal `NotesEditorViewModel` placeholder — flagged in the commit message as a Stage-B-alignment checkpoint, NOT a permanent contract.

---

## 8. Dependencies on other stages

- **Stage B (editor + persist) — HARD.** Stage E cannot land before Stage B ships `NotesEditorView` + `NotesEditorViewModel`. If Stage B's plan picks AttributedString over Markdown, Stage E's §2, §4, §5 all need coordinated revision; flag to user before executing.
- **Stage C (FTS5 search) — SOFT (acknowledge coupling).** With Markdown storage, searching `bold` will hit `**bold**`. Two options for Stage C:
  - (a) Accept false-positives for now (Stage E does nothing; Stage C can normalise query or results at its own cost).
  - (b) Stage C maintains a derived `body_plaintext` shadow column stripped of Markdown markers, indexed by FTS5; `body` stays the source of truth. Stage E does not commit to either; the Markdown formatter functions Stage E ships are pure and easy for Stage C to call from a stripper.
- **Stage D (tags) — NONE.** Tags live in a separate column / relation (see BACKLOG #014). No interaction with the format toolbar.
- **Ticket #011 (repo delete) — NONE.** Different surface (sidebar / repo list), not the editor.

---

## 9. Open questions

1. **Markdown render mode.** Stage E ships always-markers-visible (Obsidian source mode). Is that acceptable for dogfood, or does the user expect rendered-on-blur (Notion live-preview) in Stage E itself? Follow-up stage, not blocker.
2. **Bullet marker glyph.** `- ` (current recommendation, GitHub-flavoured) vs `* ` (CommonMark-traditional) vs `• ` (pretty but not round-trip-safe to external Markdown). Pick one; lock in a test.
3. **Existing plaintext transcripts on first format.** When a pre-Stage-E transcript is opened and the user clicks Bold, do we silently treat the plaintext as Markdown (current plan), or show a one-time "Convert to formatted note?" confirmation? Current plan = silent treat-as-Markdown (plaintext is valid Markdown).
4. **Bold/italic marker style.** `**…**` vs `__…__` for bold; `*…*` vs `_…_` for italic. Recommend `**` / `*` (consistent with export-to-GitHub / Slack). Lock in test.
5. **Selection range on wrap.** After `"world"` → `"**world**"`, does the selection become `"**world**"` (6 chars, includes markers) or stay `"world"` (re-anchored inside the wrap)? Ergonomic answer: re-anchor inside. Lock in test.
6. **⌘K conflict.** Some macOS text fields use ⌘K as "clear to end of line" (Terminal, Emacs-bindings). Confirm no conflict when editor is first responder; if conflict exists in practice, fallback is ⌘⇧K.

---

## 10. Scope cuts within Stage E

Explicitly out of Stage E (not follow-ups, not hidden work):

- Headings (`#`, `##`, `###`).
- Numbered lists (`1. `).
- Code blocks (`` ``` ``), inline code (`` ` ``).
- Tables.
- Images / image paste.
- Colours / highlights.
- Strikethrough.
- Inline citations.
- LaTeX / math.
- Rendered-on-blur WYSIWYG.
- Find-and-replace formatting.
- Format-paint / copy-style.
- Export to PDF / DOCX / HTML.
- Syntax highlighting inside code blocks.
- Collaborative editing, live cursors, presence.
- Spell-check customisation (system default applies).

---

## 11. Risks

1. **Stage B format flip mid-execution.** If Stage B commits to AttributedString after Stage E has started, §§2/4/5 need rework. Mitigation: Stage E first commit (5.1) only adds the toolbar view + stubbed actions — actual formatters (5.2+) don't land until Stage B's storage choice is confirmed. Stage E's execution runbook MUST re-read Stage B's plan doc at kick-off.
2. **AppKit↔SwiftUI bridging complexity.** `NSTextView` inside `NSViewRepresentable` with two-way bindings on selection + focus is a known footgun on macOS 14 (selection-lost-on-update, first-responder thrash). Mitigation: lean on the existing `VisualEffectBlur` pattern; if Stage B has already chosen a bridging approach, adopt it verbatim; add MV entries for any regression-prone seam.
3. **⌘K and ⌘⇧8 system conflicts.** ⌘K collides with "clear to end of line" in some contexts; ⌘⇧8 is browser zoom-in on some Safari configs (global scope vs first-responder scope differ). Mitigation: shortcuts are scoped via `.keyboardShortcut` on buttons inside the editor view hierarchy — not global — so they only fire when the editor (or its toolbar) is focused. Verify in MV-NOTES-FMT-07.
4. **FTS5 false-positives on Markdown markers.** Search for `bold` matches `**bold**`. Mitigation: acknowledged in §8; Stage C decides (Stage E ships pure stripper helpers for Stage C to call if needed).
5. **Accessibility of custom toolbar buttons.** Custom `.buttonStyle(.plain)` loses default AppKit accessibility affordances (focus ring, highlight). Mitigation: explicit `accessibilityLabel` + `accessibilityAddTraits(.isSelected)` + `.help(…)` on every button; MV-NOTES-FMT-06 is the runbook gate.
6. **Undo-redo coherence.** Each formatter mutation should be a single undo group so ⌘Z reverts the whole toggle, not a byte-level splice sequence. Mitigation: wrap each formatter call in `NSTextView`'s `undoManager.beginUndoGrouping()` / `endUndoGrouping()` (or the SwiftUI-layer equivalent if Stage B uses `TextEditor`). MV-NOTES-FMT-02 gates.
