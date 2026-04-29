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
2. Tap the red Delete this mode card → confirm.
3. Expect: list pops back to root, row is gone.
4. Expect: no row shows a filled star (built-in fallback drives the
   next session).
5. Trigger a recording — verify the dictation fallback recipe runs
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
