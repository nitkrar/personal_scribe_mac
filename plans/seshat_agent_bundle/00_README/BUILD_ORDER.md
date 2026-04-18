# Seshat Agent Build Order

Build in strict sprint order. Never start a sprint until the previous one is merged.

## Sprint 1 — Foundations (no dependencies)
- **Agent 1:** Build all components in `01_Foundations/` — `SeshatLogoView`, `WaveformView`, `StatusPill`, `TagChip`, `ActionButton`, and `SeshatTheme` (colour/typography tokens).
- **Agent 2:** Build `AppState`, `AudioEngine`, `TranscriptStore`, and `IntentClassifier` stubs (no UI, pure logic).

## Sprint 2 — Composites + Pill (depends on Sprint 1)
- **Agent 1:** Build `ResponseCard` first (no external dependencies), then `PillOverlayWindow` using `SeshatLogoView`, `WaveformView`, `ResponseCard`. Reference: `03_Surfaces/PillOverlayWindow/`.
- **Agent 2:** Build `TranscriptRow`, `ModeCard`, `AudioPlayerThumbnail`, `TagChip`. No dependency on Agent 1's Sprint 2 work — can proceed in parallel. Reference: `02_Composites/component_map.png`.

## Sprint 3 — Surfaces (depends on Sprint 2)
- **Agent 1:** Build `NotesWindow` (sidebar + editor + context panel). Reference: `03_Surfaces/NotesWindow/`.
- **Agent 2:** Build `SettingsWindow` (Modes tab) and `OnboardingWindow`. Reference: `03_Surfaces/SettingsWindow/` and `03_Surfaces/OnboardingWindow/`.
- **Agent 3:** Wire `MenuBarMenu` to `AppState`. Reference: `03_Surfaces/MenuBarMenu/`.

---

## Shared Files — NEVER Duplicate, Always Import

| File | Purpose |
|---|---|
| `SeshatTheme.swift` | All colour, typography, and spacing tokens for dark + light mode |
| `SeshatLogoView.swift` | The quill icon — single source of truth |
| `WaveformView.swift` | The animated waveform — single source of truth |
| `TranscriptStore.swift` | The data model for all transcripts and notes |
| `AppState.swift` | The single observable state machine for the whole app |

## Asset Locations

| Asset | Path |
|---|---|
| Logo (dark mode) | `01_Foundations/assets/logo_dark.png` |
| Logo (light mode) | `01_Foundations/assets/logo_light.png` |
| Logo animation states | `01_Foundations/assets/logo_animation_states.png` |
| Colour system reference | `01_Foundations/assets/colour_system.png` |
| Component map | `02_Composites/component_map.png` |
