# Hotkeys — Manual Verification Runbook

Hotkey routing depends on global `NSEvent` monitoring and app lifecycle
integration that XCTest cannot fully prove in-process. Run the checklist
below after changes in `Sources/SeshatAppKit/Hotkeys/` or the hotkey
composition wiring.

- [ ] triple-tap Option quits the app within ~1s
