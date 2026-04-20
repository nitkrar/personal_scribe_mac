# Manual Notes Verification

- Open the status-item `History` row after onboarding is completed and confirm a single `<AppBrand.displayName> History` window opens in front of the app.
- Close the window, open `History` again, and confirm the same window instance is reused rather than spawning duplicates.

## Empty state

- Point `<AppBrand.displayName>` at a clean base directory with no persisted transcripts, open `History`, and confirm the sidebar shows `No transcripts yet`.
- In the same empty-state run, confirm the center editor shows `Select a transcript to view its text.` and the right-side panel shows `Select a transcript to inspect its metadata.`

## Sidebar shows recent entries

- Record at least two short dictations, open `History`, and confirm both entries appear in the sidebar ordered newest-first.
- Confirm each sidebar row shows a readable title/preview derived from the transcript text plus the relative timestamp on the trailing edge.

## Search filters list

- Type a unique word from one transcript into the search field and confirm the sidebar narrows to the matching transcript only.
- Clear the search field and confirm the full history list returns.

## Selecting entry shows text

- Click a non-selected transcript in the sidebar and confirm the center editor switches to that transcript's full text.
- Re-select the newer transcript and confirm the editor switches back without opening a second window.

## Context panel shows metadata

- With a transcript selected, confirm the right-side `Details` panel shows `Recorded`, `Audio Duration`, and `Processing` values for that entry.
- Confirm the panel does not show a broken audio-thumbnail placeholder when no audio-file reference is available.
