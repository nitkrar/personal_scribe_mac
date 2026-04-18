# MenuBarMenu — Build Reference

## Architecture Decision: Native NSMenu

The `MenuBarMenu` is a **native AppKit `NSMenu`**, not a SwiftUI popover or custom view.

### Menu Items (in order)
1. `Quick Memo` — non-interactive mode name header (grey, disabled)
2. `Start Recording  ⌥⌘` — toggles to "Stop Recording" when active
3. `History` — opens `NotesWindow`
4. `Settings` — opens `SettingsWindow`
5. `---` separator
6. `Quit Seshat`

### What NOT to build
- No SwiftUI views inside this menu
- No transcript preview row
- No status dot or `StatusPill`
- No logo/quill icon inside the dropdown (the icon lives on the `NSStatusItem` button only)

### Menu Bar Status Item Icon
The icon in the menu bar row is a static `NSImage` set on `NSStatusItem.button?.image`.
Export the quill mark from `01_Foundations/assets/logo_dark.png` at 18×18pt @2x as a template image.
Do **not** instantiate `SeshatLogoView` here.

> **Note:** The file `menu_design.png` in this folder shows an earlier rich popover design that was superseded. Use this `IMPORTANT.md` as the authoritative reference.
