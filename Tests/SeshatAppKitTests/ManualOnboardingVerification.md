# Onboarding Window — Manual Verification Runbook

This slice rewrites first-run onboarding from a stepped flow into a
single-screen checklist. XCTest covers the checklist state model and
completion actions, but the actual SwiftUI layout and macOS permission
prompts still require runtime verification.

---

## Single-screen first launch

- [ ] **MV-OB-1** Fresh install / fresh defaults: launch Seshat and confirm a single dark onboarding window appears with the centered quill logo, centered `Welcome to Seshat` heading, centered `Your personal AI scribe` subtitle, three checklist rows, the AI-model note, the reassurance caption, one full-width `Continue` button, and a `Skip setup` link.
- [ ] **MV-OB-2** Without granting Microphone or Input Monitoring, confirm `Continue` is disabled and the hint `Grant Microphone and Input Monitoring to continue.` is visible.
- [ ] **MV-OB-3** Click the `info.circle` button on each row and confirm the matching explanatory popover opens for Microphone Access, Input Monitoring, and Accessibility.

## Permission states

- [ ] **MV-OB-4** Grant Microphone and Input Monitoring. Confirm each granted row flips to a green check icon, each status changes to `Granted`, and `Continue` becomes enabled even if Accessibility is still unresolved.
- [ ] **MV-OB-5** On the Accessibility row, use `Skip` or deny the macOS prompt. Confirm the row switches to a yellow warning state, shows `Skipped` or `Open Settings` as appropriate, and renders `Seshat will not be able to paste into other apps. Transcripts still copy to clipboard.`
- [ ] **MV-OB-6** Deny Microphone or Input Monitoring and confirm the affected row shows `Open Settings` while `Continue` remains disabled.

## Completion paths

- [ ] **MV-OB-7** With Microphone and Input Monitoring granted, click `Continue`. Confirm the window closes whether Accessibility is granted, denied, or skipped.
- [ ] **MV-OB-8** Relaunch from a fresh-defaults state, click `Skip setup`, and confirm the window closes immediately and onboarding does not appear automatically on the next launch.
