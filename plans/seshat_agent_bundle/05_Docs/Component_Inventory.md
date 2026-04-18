# Seshat Component Inventory & Build Sequence

To prevent code duplication when using parallel AI agents, the UI must be broken down into reusable SwiftUI components. Agents must build the foundational components first before assembling the complex views.

## 1. Foundational Components (Build First)

These components have no dependencies and are used across multiple surfaces. **Agent A** should build these before any other UI work begins.

| Component Name | Description | Used In |
|---|---|---|
| `SeshatLogoView` | The static diagonal quill icon. Accepts a `size` and `color` parameter. | Pill, Onboarding, Notes. **Note:** The menu bar status item icon is a static `NSImage` asset (exported from the same quill mark), not a live SwiftUI `SeshatLogoView`. |
| `WaveformView` | The horizontal sine wave that animates based on an `audioLevel` binding. | Pill, Notes (Linked Recordings) |
| `StatusPill` | A small rounded rectangle with a colored dot and text (e.g., "Ready", "Recording"). | Settings, Onboarding. **Note:** The menu bar is a native `NSMenu` and cannot host SwiftUI components. State is communicated via the menu bar icon image swap (idle quill → animated quill), not via `StatusPill`. |
| `TagChip` | A small rounded rectangle for metadata tags (e.g., "meeting"). | Notes Sidebar, Notes Editor |
| `ActionButton` | Standardized button style (e.g., the champagne "Continue" or "Save" buttons). | Onboarding, Settings |

## 2. Composite Components (Build Second)

These components rely on the foundational components. They can be built in parallel by **Agent B** and **Agent C** once Phase 1 is complete.

| Component Name | Description | Dependencies | Used In |
|---|---|---|---|
| `TranscriptRow` | A reusable list item showing title, timestamp, and truncated text. | None | History Panel, Notes Sidebar |
| `ModeCard` | A compact row showing a Voice Model + AI Model preset. | `StatusPill` | Settings (Modes) |
| `AudioPlayerThumbnail` | A compact audio player showing duration and a static waveform. | `WaveformView` | Notes Context Panel |
| `ResponseCard` | The temporary overlay card for Command Mode responses. | `SeshatLogoView` | Command Mode |

## 3. Core Surfaces (Build Third)

These are the main application windows and panels. They assemble the composite components. Assign one agent per surface to avoid merge conflicts.

| Surface Name | Description | Key Dependencies |
|---|---|---|
| `PillOverlayWindow` | The floating `NSPanel` that houses the `SeshatLogoView` and `WaveformView`. Handles the 3 visibility modes. | `SeshatLogoView`, `WaveformView`, `ResponseCard` |
| `MenuBarMenu` | The native `NSMenu` dropdown triggered from the status item. Items: active Mode name (non-interactive header), Start/Stop Recording `⌥⌘`, History, Settings, Quit. No SwiftUI components. No state display or transcript previews. | None (Native AppKit only) |
| `SettingsWindow` | The multi-tab settings interface, specifically the Modes tab. | `ModeCard`, `ActionButton` |
| `NotesWindow` | The 3-column personal knowledge base interface. | `TranscriptRow`, `TagChip`, `AudioPlayerThumbnail` |
| `OnboardingWindow` | The first-run permission flow. | `SeshatLogoView`, `ActionButton` |

## 4. Parallel Agent Sequencing Plan

To execute this build with multiple agents, follow this strict sequence:

**Sprint 1: Foundations & State**
- **Agent 1:** Build `SeshatLogoView`, `WaveformView`, and `StatusPill`.
- **Agent 2:** Build the core State Machine (`AppState`, `AudioEngine`, `IntentClassifier` stubs).

**Sprint 2: Composites & Overlays**
- **Agent 1:** Build `ResponseCard` first, then `PillOverlayWindow` (which depends on `ResponseCard`). Integrate the waveform animation.
- **Agent 2:** Build `TranscriptRow`, `ModeCard`, `AudioPlayerThumbnail`, and `TagChip`. These have no dependency on Agent 1's Sprint 2 work.

**Sprint 3: Main Surfaces**
- **Agent 1:** Build `NotesWindow` (assembling the sidebar, editor, and context panel).
- **Agent 2:** Build `SettingsWindow` (Modes architecture) and `OnboardingWindow`.
- **Agent 3:** Wire up the `MenuBarMenu` to the State Machine.
