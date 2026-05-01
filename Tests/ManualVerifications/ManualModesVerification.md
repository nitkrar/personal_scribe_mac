# Manual verification — #089 Modes editor

Exercise these steps in a release DMG (or `.app` from `swift run`) once
the implementation lands. SwiftUI surfaces under push-nav can't be
unit-tested end-to-end; runtime verification is the only proof.

Prerequisite: at least one ASR voice model is downloaded in the AI
Models tab (otherwise every mode shows the validity warning). Some
steps additionally require streaming ASR / diarization models.

## MV-MODES-1 — First launch is empty
1. Wipe `~/Library/Application Support/com.nitkrar.personal_scribe/workflow-modes.json`.
2. Launch app → Modes tab.
3. Expect: empty-state copy ("No modes yet. Tap + to create one.")
   + a primary `+ Create your first mode` button.
4. Expect: no rows; no built-in `Dictation` row visible.

## MV-MODES-2 — Preset popover seeds a mode
1. Tap `+` in the toolbar.
2. Pick `Dictation` from the popover.
3. Expect: row appears with name "Dictation" + mic glyph.
4. Expect: detail view pushes immediately; title field reads "Dictation".

## MV-MODES-3 — Inline title edit autosaves
1. From step 2, tap the title in the detail header.
2. Type `Med Notes` then blur.
3. Tap the back arrow → row reflects "Med Notes".
4. Restart the app → row still says "Med Notes".

## MV-MODES-4 — Star tap sets default + persists
1. Create two modes (any preset).
2. Tap the star on the second row.
3. Expect: star fills (champagne); first row's star (if any) un-fills.
4. Restart → recording now starts in the second mode (verify via
   menu-bar mode submenu showing it as current).

## MV-MODES-5 — Drag-reorder persists across restart
1. With ≥3 modes, drag the third row to the top from the row body (no edit mode / reorder handle required).
2. Restart → list order matches.
3. Open menu-bar mode submenu → reflects new order.

## MV-MODES-6 — Validity gating for streaming preset
1. Without a streaming ASR model downloaded, create a `Streaming
   Dictation` preset.
2. Expect: orange warning chip "Realtime requires a streaming ASR model".
3. Tap the star → no-op (star stays unfilled), red error toast.
4. Download the streaming model in AI Models tab.
5. Expect: warning chip clears within ~1s; star tap now works.

## MV-MODES-7 — Reset-to-default at app start
1. Set Mode A as default (star filled).
2. Use the menu-bar switcher to flip current to Mode B.
3. Verify recording uses Mode B (until app restart).
4. Quit + relaunch.
5. Expect: current resolves back to Mode A — pre-#089 we never
   persisted the menu-bar pick, and #089 explicitly resets-to-default
   per L-6.

## MV-MODES-8 — Delete-default clears default
1. With Mode A as default, navigate into its detail.
2. Tap the red Delete this mode card.
3. Expect: confirmation alert appears on the detail screen.
4. Confirm delete.
5. Expect: list pops back to root, row is gone.
6. Expect: no row shows a filled star (built-in fallback drives the
   next session).
7. Trigger a recording — verify the dictation fallback recipe runs
   (auto-paste / auto-stop driven by GeneralTab).

## MV-MODES-9 — GeneralTab toggles drive the fallback
1. With no custom modes (or no default), open GeneralTab.
2. Toggle Auto-paste OFF.
3. Trigger a recording.
4. Expect: transcript lands in clipboard; no Cmd+V fired.
5. Toggle Auto-stop OFF.
6. Trigger a long recording with silence — VAD does not auto-stop.
7. Toggle them back; rerun — paste + auto-stop return.

## MV-MODES-10 — Per-mode hotkey activates + records
1. Pick a mode, open detail, tap `Set hotkey` and capture a unique chord
   (e.g. ⌃⇧F1).
2. Confirm the recorder closes; the card shows the captured chord.
3. With Ninimma in the background, press the chord.
4. Expect: recording starts; the registry's current mode flips to
   this mode (verify via pill / menu-bar).
5. Release to stop.

## MV-MODES-11 — Per-mode hotkey collision
1. From step 10, on a SECOND mode, attempt the same chord.
2. Expect: the recorder UI surfaces "Already in use by another mode
   or hotkey." Confirm button stays disabled.
3. Try a chord that matches the global recording hotkey.
4. Expect: same rejection.

## MV-MODES-12 — Realtime + diarization toggles
1. Create a mode; in detail flip Realtime ON.
2. Expect: diarization toggle disables (V1 limitation).
3. Save; activate; record.
4. Expect: partial transcripts stream as you speak (if streaming
   ASR model is downloaded).
5. Flip Realtime OFF; flip Identify Speakers ON; record a 2-speaker
   conversation (if diarization model is downloaded).
6. Expect: transcript shows per-speaker turns.

## MV-MODES-13 — Per-mode voice-model picker (#090)
Prerequisite: at least two ASR voice models downloaded (e.g.
Parakeet TDT 0.6B v2 and Parakeet TDT-CTC 110M).

1. Set the GLOBAL active ASR model in AI Models tab to model A
   (e.g. v2).
2. Open Modes tab → tap a custom mode (or create one).
3. In the detail view, the "Voice model" row shows
   `Use globally active (<A name>)` as the caption + a `Globally
   active` button.
4. Click the button to open the menu. Expect:
   - First item: `✓ Use globally active (<A name>)`.
   - Divider.
   - One item per enabled descriptor of the relevant kind.
5. Pick model B (e.g. 110M).
6. Expect: caption flips to `Pinned to <B name>`; button label
   shows `<B name>`.
7. Restart app → mode still pinned to B.
8. In AI Models tab, switch GLOBAL active back to A.
9. Return to the mode's detail. Expect: still pinned to B (caption
   `Pinned to <B name>`).
10. Trigger recording for this mode → transcript uses model B (the
    pin), not the globally-active A.

## MV-MODES-14 — Pinned mode survives global swap (#090)
1. From MV-MODES-13 step 6, with the mode pinned to B.
2. In AI Models tab, deactivate (or set a different active) for the
   ASR kind.
3. The unpinned `Dictation` built-in fallback would now have no
   active ASR model. But the pinned mode still validates and runs.
4. Modes tab: pinned mode shows green "valid" indicator (no warning).
5. Trigger recording on the pinned mode → it works (uses B).

## MV-MODES-15 — Removed-pin model surfaces invalidity (#090)
This step requires editing `workflow-modes.json` directly OR pinning
to a model and then disabling its catalog entry via a build that
sets `isEnabled: false` on the descriptor.

1. With a mode pinned to model B, edit
   `~/Library/Application Support/com.nitkrar.personal_scribe/workflow-modes.json`
   and change the `descriptorID` to a non-existent id (e.g.
   `"deleted-model"`).
2. Restart app → Modes tab.
3. Expect: orange "invalid" chip on the mode's row with copy
   `Pinned model "deleted-model" is no longer available. Pick
   another in the mode's settings.`
4. Open the mode's detail. Voice model card caption:
   `Pinned model unavailable`. Button: `Unknown model`.
5. Open the picker, choose a valid model (or `Use globally active`).
6. Caption + chip clear.
7. Menu-bar mode submenu: with the mode invalid (step 3), it does
   NOT appear in the submenu. After repair (step 5), it reappears.

## MV-MODES-16 — Per-mode hotkey doesn't fire for invalid modes (#090 follow-up)
1. Pick a mode and capture a per-mode hotkey (e.g. ⌃⇧F2). Confirm
   the chord works (recording starts when pressed).
2. Quit the app.
3. Edit `~/Library/Application Support/personal_scribe/workflow-modes.json`
   to set the mode's pin (`descriptorID`) to a non-existent id.
4. Relaunch.
5. Press the chord. Expect: nothing happens (no recording, no error
   toast). The hotkey table now refuses to register an invalid
   mode's chord.
6. Repair the pin via the Modes editor picker.
7. Press the chord again. Expect: recording starts as in step 1.

Limitation: the hotkey table re-fires only on mode-list changes
(create / save / delete / reorder). If the mode is invalid because
of a model state change (e.g. user deleted the active descriptor in
AI Models tab), the hotkey stays registered until the next
mode-list event or app restart. Acceptable trade-off for V1.

## MV-MODES-17 — Streaming preset seeds #056 defaults
1. Tap `+` in the toolbar.
2. Pick `Streaming Dictation`.
3. Expect: the detail view opens with `Realtime` already ON.
4. Expect: the realtime-only rows are visible:
   `Live transcript card`, `Live cursor streaming`, and
   `Authoritative second pass`.
5. Expect: `Live transcript card` resolves ON, `Live cursor streaming`
   resolves OFF, and `Authoritative second pass` resolves ON unless you
   have changed the global defaults in Settings.
6. Expect: VAD auto-stop resolves OFF for this preset by default.

## MV-MODES-18 — Per-mode streaming overrides beat globals
1. In `Settings → General`, set global `Live transcript card` OFF and
   `Authoritative second pass` OFF.
2. Return to the streaming mode from MV-MODES-17.
3. Override that mode to `Live transcript card = ON` and
   `Authoritative second pass = ON`.
4. Quit + relaunch.
5. Expect: the mode still shows the explicit overrides, not the global
   OFF defaults.
6. Record with that mode. Expect: a live StreamCard appears during
   capture and stop-time finalization still uses the authoritative
   second pass when an ASR model is available.
