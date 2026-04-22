# Manual Transcriptions Verification

SwiftUI hover state and pointer-driven row actions are runtime-only on
macOS. Use this runbook after changes to the Transcriptions tab delete
affordance.

- [ ] **MV-DEL-1** Seed at least two transcripts, open the `Transcriptions`
  tab, and move the pointer across the list. Confirm only the hovered
  detail row reveals a trailing trash icon. The `Home` tab's recent rows
  must remain read-only with no trash affordance.
- [ ] **MV-DEL-2** Click the trash icon on a hovered Transcriptions row.
  Confirm deletion is immediate with no confirmation sheet, the deleted
  row disappears from the list right away, and date buckets/search
  results update to reflect the removal.
- [ ] **MV-DEL-3** With the unified window still open, switch to `Home`
  after deleting a transcript and confirm the recent list and weekly
  rollups reflect the updated SQLite history exactly once.
- [ ] **MV-DEL-4** Relaunch the app and confirm the deleted transcript
  does not return. If the deleted row had an `audioFilePath`, confirm
  only the database row is gone; the audio file itself remains on disk
  for ticket `#069`.
