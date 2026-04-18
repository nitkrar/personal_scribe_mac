# Seshat UX Redesign & Architecture Proposal

This document outlines the complete UX redesign, unified UI architecture, and critical bug fixes for the Seshat macOS application. The goal is to transform the current unpolished experience into a modern, minimal, and highly responsive personal AI scribe.

## 1. Visual Identity & Logo System

The new visual identity strips away heavy ornamentation in favour of a clean, unified system based on a single flowing quill.

**The Core Concept:**
The logo consists of two distinct elements:
1. **The Static Mark:** A diagonal quill feather with a seamless nib. This element never moves or animates.
2. **The Live Waveform:** A horizontal sine wave that passes through the feather. This is the only element that animates, changing amplitude based on audio input.

This separation of concerns ensures the brand mark remains recognizable at all times, while the animation clearly communicates system state without visual noise.

![Logo Animation States](quill_states_final.png)

## 2. Unified UI Architecture

The previous design suffered from redundant UI surfaces (a heavy menu bar popover and a separate pill overlay). The new architecture unifies the experience: **The Pill is the single UI surface. The menu bar is purely a trigger.**

### The Menu Bar Trigger
The menu bar dropdown is a native `NSMenu` (AppKit). It provides context (the active mode name as a non-interactive header) and actions only — no state display, no transcript previews, no SwiftUI components. The menu items are: active Mode name, Start/Stop Recording `⌥⌘`, History, Settings, Quit.

> **Architecture Decision (confirmed):** An earlier mockup (`menu_design.png`) showed a rich SwiftUI popover card. This was superseded by the unified architecture decision. The correct implementation is the native `NSMenu`. The `menu_design.png` asset in the bundle is retained for historical reference only and should not be used as a build reference.

### The Pill Lifecycle
The pill is the single source of truth for state and animation. It supports three visibility modes:
1. **Always On:** The pill sits at the bottom of the screen, showing an idle state (compact) and expanding when recording.
2. **Auto-show:** The pill is hidden at rest. It slides up when recording starts, shows controls, displays "Done" when transcription finishes, and then fades out.
3. **Hidden:** The power-user mode. The pill never shows. The user relies entirely on hotkeys and the menu bar.

![Unified Architecture](mockup_unified_architecture.png)

## 3. Colour System (Dark & Light Mode)

The colour palette has been refined to a sophisticated "Champagne" accent on deep, near-black backgrounds for dark mode, and warm off-white for light mode.

![Colour System](colour_system.png)

### Light Mode Implementation
The light mode variant maintains the same minimal aesthetic, using a clean white surface for the pill and menu dropdown, with the champagne accent darkened slightly (`#6B6760`) to ensure accessible contrast against light backgrounds.

![Light Mode Mockup](mockup_lightmode.png)

## 4. Multi-Model "Modes" Architecture

To support multiple AI models (local Parakeet, cloud Whisper, Llama instructions) without cluttering the UI, the settings panel introduces the concept of **Modes**.

A Mode is a custom preset that combines:
- A Voice Model (e.g., Parakeet TDT)
- An AI Model (e.g., GPT-4.1 mini)
- A System Prompt (e.g., "Clean up filler words, format as meeting notes")

Users can switch Modes quickly from the menu bar before recording, ensuring the right AI pipeline is used for the right context.

![Settings & Modes](mockup_03v2_settings.png)

## 5. Onboarding & History

The redesign introduces a clean first-run onboarding flow to handle permissions gracefully, including an optional Accessibility step. The History panel provides a searchable list of past transcripts, solving the issue of overwritten data.

![Onboarding and History](mockup_04v2_onboarding.png)

## 6. Critical Bug Fixes & Code Recommendations

The following bugs were identified in the current repository and must be addressed to ensure a stable foundation for the redesign.

### BUG-01: App Unresponsive at Launch
**Issue:** `RecordButtonModel` calls `WhisperModelLoader.load()` synchronously on the main thread during `init`. The app freezes for 2–8 seconds while the model loads.
**Fix:** Move model loading to a background `Task`. Publish an `isModelReady: Bool` state. Disable the Record button and show a "Preparing..." state until the model is loaded.

```swift
// Example Fix
Task {
    await WhisperModelLoader.shared.load()
    DispatchQueue.main.async {
        self.isModelReady = true
    }
}
```

### BUG-02: Pill Clicks Fail on macOS 14
**Issue:** `OverlayController` uses SwiftUI's `.onTapGesture` on the pill view. On macOS 14, tap gestures on `NSHostingView`-backed overlays with `NSPanel` fail silently.
**Fix:** Replace `.onTapGesture` with an `NSClickGestureRecognizer` attached directly to the `NSHostingView`, or handle `mouseDown` events in a subclassed `NSPanel`.

### BUG-03: Missing Microphone Permission Handling
**Issue:** If the user denies microphone access, the Record button remains enabled but recording silently fails.
**Fix:** Check `AVCaptureDevice.authorizationStatus(for: .audio)` before starting. If `.denied`, display an inline banner with a deep-link to System Settings.

### BUG-04: Global Hotkey Fails Silently
**Issue:** `CGEventTap` registration returns `nil` when Input Monitoring permission is missing, but the app does not notify the user.
**Fix:** Check the return value of `CGEvent.tapCreate`. If `nil`, surface a warning pointing the user to Privacy & Security > Input Monitoring.

### BUG-05: Transcript Overwritten
**Issue:** The app stores a single `lastTranscript: String`, overwriting it on every new recording.
**Fix:** Implement a `[TranscriptEntry]` array and persist it to `UserDefaults` or SQLite. Build a History panel to view past recordings.

### BUG-08: Missing Transcribing State
**Issue:** When recording stops, the UI immediately reverts to "Start Recording" while Whisper processes the audio in the background, making the user think the recording failed.
**Fix:** Introduce a `.transcribing` state. The pill should show a flat waveform with a spinner, and the menu button should read "Transcribing..." until the text is ready.

## 7. Implementation Roadmap

To execute this redesign efficiently, follow this prioritized sprint plan:

**Phase 1: Stability (The Bugs)**
- Fix the synchronous model loading (BUG-01) to unblock the main thread.
- Fix the macOS 14 pill click issue (BUG-02).
- Implement proper permission handling for Mic and Input Monitoring (BUG-03, BUG-04).
- Add the `.transcribing` state to the state machine (BUG-08).

**Phase 2: The Unified Architecture**
- Strip the menu bar popover down to the minimal native menu design.
- Rebuild the Pill overlay to support the three visibility modes (Always On, Auto-show, Hidden).
- Implement the new logo and waveform animation system.

**Phase 3: Features & Polish**
- Build the History array and UI panel (BUG-05).
- Implement the "Modes" architecture in Settings.
- Apply the Dark/Light mode colour tokens across all surfaces.

## 8. Future Evolution: The Intent Layer & Command Mode

To evolve Seshat from a passive transcription tool into an active, Siri-style assistant, the architecture must support intent classification. This allows the app to distinguish between dictation, commands, and queries.

### The Intent Layer Architecture
The core addition is an **Intent Classifier** that sits between the transcription engine and the output surface.

![Intent Layer Architecture](mockup_intent_layer.png)

When a transcript is generated, the classifier routes it:
- **Dictation:** Written directly to the clipboard and Notes store.
- **Command:** Sent to an Action Dispatcher (e.g., `NSWorkspace` or API) to trigger system or app-specific actions.
- **Query:** Sent to the Notes Surface to search the personal knowledge base.

### Command Mode Pill Interactions
To support this evolution without cluttering the UI, the pill remains clean. Responses are surfaced contextually via temporary overlay cards that slide up from the pill and auto-dismiss.

![Command Mode Pill States](mockup_command_mode_pill.png)

### The Notes Surface (Personal Knowledge Base)
To support queries ("What did I say about the Q3 budget?"), Seshat requires a long-term memory. The Notes Surface is a dedicated window that auto-ingests transcripts, supports manual editing, and allows tagging and full-text search.

![Notes Surface](mockup_notes_surface.png)

This transforms Seshat into a searchable personal knowledge base, making the app more valuable the longer it is used.
