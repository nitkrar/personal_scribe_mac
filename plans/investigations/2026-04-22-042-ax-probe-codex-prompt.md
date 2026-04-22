You are investigating bug #042 in Ninimma, a Swift macOS menu-bar dictation app at /Users/nitinkum/Projects/nitkrar/personal_scribe. RESEARCH ONLY — do NOT edit source code, do NOT run `swift build` / `swift test` / `sl`. This is a scoping / design pass to pick a fix direction, not to implement the fix.

## Think extensively before concluding.

Take your time. Read the code before making any claim. Every assertion needs a file:line reference. Do not handwave. No "the ticket says X so it's true" — verify against the code. Think through edge cases explicitly. Ultrathink-level reasoning is warranted.

Target output length: 500–900 words. Be precise, not padded.

## Bug — BACKLOG.md #042 verbatim

```
### #042 — AX probe rejects custom-drawn editors (Sublime), regressing auto-paste

`bug` · `P1` · `open` · `area: output, paste`
*Updated 2026-04-21*

Since the 2026-04-20 paste-target redesign (`ClipboardBatchOutput.swift:107-116`), auto-paste is gated on `focusedElementHasCursor()` (`:220-259`) which only returns `true` when one of these holds:
- `kAXInsertionPointLineNumberAttribute` readable, OR
- `kAXSelectedTextAttribute` readable, OR
- role ∈ {`kAXTextFieldRole`, `kAXTextAreaRole`, `kAXComboBoxRole`}.

Custom-drawn editors whose text surface doesn't expose standard AX attributes fail the probe even when the user genuinely has a cursor in the focused app. **Confirmed on Sublime Text** (2026-04-21 runtime session); suspected: VS Code, some Electron apps, Chrome web forms. Auto-paste is skipped, the "Copied to clipboard · ⌘V to paste" card is shown, user must ⌘V manually. Affects **both** hotkey mode and pill-click mode — any path routed through `ClipboardBatchOutput.deliverBatch`.

Reproduction (2026-04-21):
- Focus Sublime with cursor in a text buffer → hotkey-record → speak → release. Transcript lands on clipboard only, no auto-paste, card appears.
- TextEdit + iTerm both paste correctly (native AX).

**Pre-regression behavior** (rollback block quoted at `ClipboardBatchOutput.swift:132-165`): the previous `resolveTarget()` path compared `NSWorkspace.frontmostApplication.bundleIdentifier` against Ninimma's own bundle — permissive enough for AX-stubborn apps. The 2026-04-20 swap was motivated by #003 (pill click briefly made Ninimma frontmost → bundle-ID check returned `.selfFrontmost` → paste skipped even with the cursor still in Slack). Now that #003 is fixed at the panel level (`canBecomeKey = false`), the bundle-ID path would no longer false-positive for the pill-click case, so we have room to loosen the probe.

**Fix direction** (options to evaluate — not locked):
1. **PID inequality check.** Paste whenever the AX focused element's owning-app PID is NOT Ninimma's PID. Still prevents pill-focus-steal regression (Ninimma-as-focused would skip); permissive for AX-weird apps.
2. **Extend accepted roles** conditional on PID ≠ Ninimma. Add `kAXGroupRole`, `kAXUnknownRole`, `kAXWebAreaRole`. Risks false positives on non-text UIs.
3. **Revert to `resolveTarget()` bundle-ID check.** Now that the pill panel doesn't become key/main, the original path may be correct again. Simplest, but loses the AX-layer defense if any future regression allows Ninimma to become frontmost.

Acceptance:
- Auto-paste lands in Sublime, VS Code, and TextEdit when a cursor is genuinely focused in them.
- Clipboard-only card only appears when the user explicitly selected clipboard-only mode, Accessibility isn't granted, OR the focused element is genuinely inside Ninimma.
- No regression on #003 (pill click must still not route paste back into Ninimma).

**Depends on:** #003 (already done) — fix direction 1/3 assumes the panel-level non-activation contract is in place.
```

## Files to read

- `Sources/PersonalScribeAppKit/Output/ClipboardBatchOutput.swift` — 270 lines; probe logic `:107-116`, live probe `:220-259`, rollback block `:132-165`.
- `Sources/PersonalScribeAppKit/Overlay/PillOverlayPresenter.swift` — #003 panel-level non-activation at `:54-84, :236`. Look for `canBecomeKey`, `canBecomeMain`, `.nonactivatingPanel`.
- Grep `Tests/` for `ClipboardBatchOutput` test file(s) — identify the probe-injection seam's existing coverage.
- Grep for `StatusItemController`, `NSStatusItem`, `NSApp.activate` — enumerate every site that could make Ninimma bundle-ID-frontmost during a paste window.
- `Sources/PersonalScribeCore/AppBrand/` — bundle identifier source.
- `Tests/PersonalScribeAppKitTests/ManualPillOverlayVerification.md` — check MV-NAP-3 (menu-bar stop path) runbook status.

## Questions to answer thoroughly

1. **Root cause — verify or refute.** Trace through `liveFocusedElementHasCursor()` for a hypothetical Sublime focus state. Does Sublime Text really expose no `kAXInsertionPoint` / `kAXSelectedText` attribute and report a non-text role? What role DOES Sublime likely report? (No live AX inspection — infer from Apple AX docs + any comments/tests in the repo.)

2. **Each fix option — concrete evidence.**
   - **Option 1 (PID inequality):** `AXUIElementGetPid` is a C function (not an attribute) — confirm signature and usage on the system-wide focused element. What non-text UIs would false-positive? (Finder sidebar, notification center, Spotlight, Dock, menu bar extras.)
   - **Option 2 (extended roles):** which real apps report each of `kAXGroupRole` / `kAXUnknownRole` / `kAXWebAreaRole` for their text surfaces? What non-text surfaces use these roles?
   - **Option 3 (revert):** enumerate every path where Ninimma could become bundle-ID-frontmost during the ~100ms paste window:
     - Hotkey release path
     - Pill click stop path (#003 fix — verify `canBecomeKey = false` actually prevents bundle-ID promotion, not just key-window promotion)
     - Menu-bar status-item Stop click path (MV-NAP-3 runbook — still open per #003 body)
     - Escape / cancel paths
     - Settings / unified window open during recording (check `UnifiedWindowController`)
     - App-switcher (Cmd-Tab) during recording

3. **Options NOT in the ticket.** Better fixes? E.g.:
   - Defense-in-depth: bundle-ID AND/OR AX probe (tiered / composed)
   - Per-app allowlist / denylist
   - Widen AX attribute set (e.g., `kAXNumberOfCharactersAttribute`, `kAXValueAttribute`, `kAXDescriptionAttribute`)
   - Walk the focused element's **parent chain** via `kAXParentAttribute` looking for a text-receptive role
   - Else: state "none worth considering" with reason.

4. **Tests.** What tests cover this code path today? Which must be updated/deleted for each option? Filenames + test names.

5. **Implementation shape.** For the option you recommend, give concrete:
   - Files touched
   - LOC added / removed (estimate)
   - Tests to add / update

## Discipline

- Open with grep, not full-file reads. Cap upfront reading at ~100 lines per file.
- Cite file:line for EVERY claim.
- If stuck after 15 min, write a `[BLOCKED]` partial to the output file and exit.
- Verify framing before labeling: don't call a symbol "dead" or "shim" without reading the declaring file.
- Do NOT run `swift build` / `swift test` / `sl`.

## Output — MANDATORY

Write your entire report to this file (create directory if missing):

  /Users/nitinkum/Projects/nitkrar/personal_scribe/plans/investigations/2026-04-22-042-ax-probe-codex.md

Output format:

```markdown
# #042 AX probe review — Codex pass (2026-04-22)

## Root cause confirmation
[paragraph with file:line evidence]

## Option 1 — PID inequality
- Concrete mechanism:
- Pros:
- Cons / failure modes:
- Feasibility: [low / medium / high] — reason

## Option 2 — extended roles
(same structure)

## Option 3 — revert to bundle-ID
(same structure)

## Alternative options
[any fix not in the 3 above, same structure — or state "none worth considering"]

## Option 3 regression risk — detailed audit
[enumerate every path that could make Ninimma bundle-ID-frontmost during the paste window; mark each safe / regressed / unknown]

## Recommended option
[1–2 sentences — pick one; state confidence level: high / medium / low]

## Implementation shape
- Files to change:
- Approx LOC delta:
- Tests to update / add:
- Behavior change summary:

## Open questions / remaining unknowns
[bullet list]
```

Length cap: 900 words. Dense and specific wins over verbose.
