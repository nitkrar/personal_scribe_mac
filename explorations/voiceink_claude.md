# VoiceInk Architecture Deep Dive

**Source:** https://github.com/Beingpax/VoiceInk (GPLv3 -- study patterns only, no code copying)
**Commit analyzed:** HEAD of main branch, cloned 2026-04-15
**Total Swift files:** 205

---

## 1. Power Mode -- Context-Aware Dictation

Power Mode is VoiceInk's most interesting feature: per-app and per-URL dictation profiles that automatically switch transcription models, AI enhancement prompts, languages, and behavior based on what the user is doing.

### Data Model

**File:** `VoiceInk/PowerMode/PowerModeConfig.swift`

```
PowerModeConfig (Codable, Identifiable)
  - id: UUID
  - name: String
  - emoji: String  (visual identifier in UI)
  - appConfigs: [AppConfig]?       (bundle IDs to match)
  - urlConfigs: [URLConfig]?       (URL patterns to match)
  - isAIEnhancementEnabled: Bool
  - selectedPrompt: String?        (UUID string of an AI prompt)
  - selectedTranscriptionModelName: String?
  - selectedLanguage: String?
  - useScreenCapture: Bool
  - selectedAIProvider: String?
  - selectedAIModel: String?
  - autoSendKey: AutoSendKey       (none/enter/shift+enter/cmd+enter)
  - isEnabled: Bool
  - isDefault: Bool                (fallback if no app/URL match)
  - hotkeyShortcut: String?        (dedicated keyboard shortcut)
```

`AppConfig` stores `bundleIdentifier` + `appName`. `URLConfig` stores a URL string pattern.

**Storage:** JSON-encoded to `UserDefaults` key `"powerModeConfigurationsV2"`. No SwiftData/CoreData for configs.

### Matching Logic

**File:** `VoiceInk/PowerMode/PowerModeConfig.swift` (PowerModeManager class)

Resolution order (first match wins):
1. **URL match** -- if active app is a browser, get the current URL and find a config with a matching `urlConfigs` entry (cleaned: lowercased, stripped of protocol/www)
2. **App match** -- find a config whose `appConfigs` contains the frontmost app's `bundleIdentifier`
3. **Default fallback** -- the config with `isDefault = true`

### Active App Detection

**File:** `VoiceInk/PowerMode/ActiveWindowService.swift`

Uses `NSWorkspace.shared.frontmostApplication` to get the active app. Called at recording start time -- NOT via a continuous polling observer. The detection happens inside `applyConfiguration()` which is called from `VoiceInkEngine.toggleRecord()`.

### Browser URL Detection

**File:** `VoiceInk/PowerMode/BrowserURLService.swift`

Supports 11 browsers: Safari, Arc, Chrome, Edge, Firefox, Brave, Opera, Vivaldi, Orion, Zen, Yandex.

Uses **compiled AppleScript files** (`.scpt` bundled in Resources) executed via `/usr/bin/osascript` as a `Process`. Each browser has its own script file (`safariURL.scpt`, `chromeURL.scpt`, etc.). The service checks if the browser is running first via `NSWorkspace.shared.runningApplications`.

### Session Management (Save/Restore)

**File:** `VoiceInk/PowerMode/PowerModeSessionManager.swift`

This is the most sophisticated part. When Power Mode activates:
1. **Captures baseline** -- saves current state (AI enhancement on/off, prompt, AI provider/model, language, transcription model) into an `ApplicationState` struct
2. **Persists session** -- encodes `PowerModeSession` (baseline + start time) to `UserDefaults` for crash recovery
3. **Applies config** -- sets all settings from the `PowerModeConfig`
4. **On end** -- restores original state from the saved session

Key design decisions:
- Session is serialized to UserDefaults, so if the app crashes during Power Mode, it recovers on next launch by restoring the baseline state
- Uses a flag `isApplyingPowerModeConfig` to prevent the `AppSettingsDidChange` notification observer from overwriting the baseline while settings are being applied programmatically
- Only captures baseline on FIRST activation -- subsequent config switches (URL changes, etc.) reuse the same session baseline

### Patterns to Reimplement for PersonalScribe

- Per-app/URL profile system with priority resolution (URL > App > Default)
- Session save/restore with crash recovery via serialized baseline state
- AppleScript-based browser URL detection (per-browser scripts)
- Guard flag to prevent notification loops during programmatic settings changes
- Auto-send keystroke after paste (Enter, Shift+Enter, Cmd+Enter)

---

## 2. Dual Engine Architecture (Whisper.cpp + FluidAudio/Parakeet)

### Unified Model Protocol

**File:** `VoiceInk/Models/TranscriptionModel.swift`

A `TranscriptionModel` protocol defines the interface:
```swift
protocol TranscriptionModel: Identifiable, Hashable {
    var id: UUID { get }
    var name: String { get }
    var displayName: String { get }
    var description: String { get }
    var provider: ModelProvider { get }
    var isMultilingualModel: Bool { get }
    var supportedLanguages: [String: String] { get }
}
```

`ModelProvider` enum covers all backends: `.local` (whisper.cpp), `.fluidAudio` (Parakeet), `.groq`, `.elevenLabs`, `.deepgram`, `.mistral`, `.gemini`, `.soniox`, `.speechmatics`, `.custom`, `.nativeApple`.

Concrete model types: `LocalModel`, `ImportedLocalModel`, `FluidAudioModel`, `CloudModel`, `NativeAppleModel`, `CustomCloudModel`.

### TranscriptionModelManager -- Unified Model Registry

**File:** `VoiceInk/Transcription/Core/TranscriptionModelManager.swift`

Acts as the single source of truth. Aggregates:
- `PredefinedModels.models` (hardcoded catalog of all known models)
- Downloaded whisper.cpp models (from `WhisperModelManager.availableModels`)
- User-imported local `.bin` files (wrapped as `ImportedLocalModel`)

Uses callback-based wiring (`onModelDeleted`, `onModelsChanged`) from both `WhisperModelManager` and `FluidAudioModelManager` to stay in sync.

Current model selection stored in `UserDefaults` key `"CurrentTranscriptionModel"` (by name string).

### TranscriptionServiceRegistry -- Service Dispatch

**File:** `VoiceInk/Transcription/Core/TranscriptionServiceRegistry.swift`

Routes transcription requests to the right service based on `ModelProvider`:
- `.local` -> `LocalTranscriptionService` (whisper.cpp via C FFI)
- `.fluidAudio` -> `FluidAudioTranscriptionService` (Parakeet via FluidAudio SPM)
- `.nativeApple` -> `NativeAppleTranscriptionService` (macOS 26+ Foundation.SpeechTranscriber)
- Everything else -> `CloudTranscriptionService`

Also handles **streaming vs. batch** dispatch:
- Creates `StreamingTranscriptionSession` for models that support streaming (ElevenLabs, Deepgram, Mistral, Soniox, Speechmatics, FluidAudio)
- Creates `FileTranscriptionSession` for batch-only models
- `StreamingTranscriptionSession` has automatic **fallback to batch** if WebSocket connection fails
- Some streaming models have batch-incompatible names, so `batchFallbackModel()` maps them (e.g., `voxtral-mini-transcribe-realtime-2602` -> `voxtral-mini-latest`)

### TranscriptionSession -- The Session Protocol

**File:** `VoiceInk/Transcription/Core/TranscriptionSession.swift`

Elegant session lifecycle abstraction:
```swift
protocol TranscriptionSession: AnyObject {
    func prepare(model: any TranscriptionModel) async throws -> ((Data) -> Void)?
    func transcribe(audioURL: URL) async throws -> String
    func cancel()
}
```

`prepare()` returns an audio chunk callback for streaming (nil for file-based). This is called during recording start, and the callback is wired to the audio recorder. The `VoiceInkEngine` buffers early audio chunks before the session is ready, then replays them.

### Whisper.cpp Integration

**File:** `VoiceInk/Transcription/Core/Whisper/LibWhisper.swift`

Wraps whisper.cpp's C API in a Swift `actor` (`WhisperContext`):
- Thread safety via actor isolation
- Uses `whisper_init_from_file_with_params` with `flash_attn = true` for Metal
- VAD (Voice Activity Detection) support via `whisper_vad_default_params`
- Reads language from `UserDefaults` at transcription time
- Prompt injection via `initial_prompt` parameter

**File:** `VoiceInk/Transcription/Core/Whisper/WhisperModelManager.swift`

Models downloaded from HuggingFace (`ggerganov/whisper.cpp`). Stored in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`. Also downloads Core ML encoder `.mlmodelc` for non-quantized models (unzipped from `.zip` via the `Zip` SPM package).

### FluidAudio/Parakeet Integration

**File:** `VoiceInk/Transcription/Batch/FluidAudioTranscriptionService.swift`
**File:** `VoiceInk/Transcription/Core/FluidAudio/FluidAudioModelManager.swift`

Uses the `FluidAudio` SPM package (binary framework from `FluidInference/FluidAudio`). Model versions: `.v2` and `.v3` (parakeet-tdt-0.6b). Download state tracked in UserDefaults (`ParakeetModelDownloaded_<name>`). Cache directory managed by `AsrModels.defaultCacheDirectory(for:)`.

Key architectural detail: VAD is applied before transcription for audio > 20 seconds. 1 second of silence is appended to short audio to capture final punctuation.

### Model Pre-warming

**File:** `VoiceInk/Services/ModelPrewarmService.swift`

Runs a tiny transcription (using bundled `esc.wav`) 3 seconds after app launch and after wake from sleep. Only for local models (Whisper/Parakeet) that need ANE compilation warmup.

### Patterns to Reimplement for PersonalScribe

- Protocol-based model abstraction with provider enum dispatch
- Service registry pattern for routing to correct transcription backend
- Session protocol with prepare/transcribe/cancel lifecycle
- Streaming with automatic batch fallback
- Audio chunk buffering during session preparation
- Model pre-warming on app launch and wake from sleep
- Actor isolation for C FFI thread safety (WhisperContext)

---

## 3. Text Injection -- Clipboard + Paste

### CursorPaster -- The Core Paste Mechanism

**File:** `VoiceInk/CursorPaster.swift`

Two paste methods, user-selectable:

**CGEvent paste (default):**
Posts `Cmd+V` via `CGEvent` with `CGEventSource(stateID: .privateState)`. Requires `AXIsProcessTrusted()`. Posts 4 events: Cmd down, V down, V up, Cmd up.

**AppleScript paste (optional, for custom keyboard layouts like Neo2):**
Pre-compiles an `NSAppleScript` on first use:
```
tell application "System Events"
    keystroke "v" using command down
end tell
```

### Clipboard Save/Restore

In `CursorPaster.pasteAtCursor()`:
1. If `restoreClipboardAfterPaste` is enabled (default: `true`), saves ALL pasteboard items (all types and data) before overwriting
2. Sets clipboard with `ClipboardManager.setClipboard()` which also:
   - Sets `org.nspasteboard.source` to the app's bundle ID
   - Optionally sets `org.nspasteboard.TransientType` (signals clipboard managers to ignore this entry)
3. Waits 50ms (`DispatchQueue.main.asyncAfter`)
4. Pastes via CGEvent or AppleScript
5. Restores original clipboard after a configurable delay (default 2.0s, minimum 0.25s)

### Auto-Send After Paste

After paste, if the active Power Mode config has `autoSendKey` set, sends the corresponding keystroke after a 500ms delay. Implemented with `CGEvent` for Enter key (virtual key 0x24) with optional Shift/Command modifiers.

### Optional Trailing Space

Controlled by `AppendTrailingSpace` UserDefault (default: `true`). Simply appends `" "` to the pasted text.

### Auto-Learn Vocabulary

**File:** `VoiceInk/Services/AutoLearnVocabularyService.swift`

After pasting, captures the focused `AXUIElement` BEFORE Cmd+V fires. After the recorder dismisses, monitors the text field for edits using an `AXObserver` and uses NLP diffing to learn corrections the user makes to the transcribed text. These become vocabulary words.

### Patterns to Reimplement for PersonalScribe

- CGEvent paste as default, AppleScript as fallback for non-standard keyboards
- Full clipboard save/restore with multi-type support (not just strings)
- Transient pasteboard type to signal clipboard managers
- Configurable restore delay
- Pre-paste focus capture for post-paste monitoring
- Two-phase monitoring: capture element during paste, start observing after recorder dismisses

---

## 4. UI Architecture -- SwiftUI + AppKit Bridging

### App Entry Point

**File:** `VoiceInk/VoiceInk.swift`

`@main struct VoiceInkApp: App` with `@NSApplicationDelegateAdaptor(AppDelegate.self)`. Everything is initialized in `init()` with careful dependency ordering:
1. SwiftData `ModelContainer` (with persistent + in-memory fallback)
2. `AIService` + `AIEnhancementService`
3. Model managers (Whisper, FluidAudio, TranscriptionModel)
4. `RecorderUIManager`
5. `VoiceInkEngine` (depends on all above)
6. Circular dependency resolution: `recorderUIManager.configure(engine:recorder:)` + `engine.recorderUIManager = recorderUIManager`
7. `HotkeyManager`, `MenuBarManager`, `ActiveWindowService`, `ModelPrewarmService`

All services injected as `@StateObject` and passed via `.environmentObject()`.

### Window Architecture

Three window types:

**1. Main Window (WindowGroup):**
- Standard SwiftUI `WindowGroup` with `.windowStyle(.hiddenTitleBar)`
- `NavigationSplitView` with sidebar listing `ViewType` enum cases
- `WindowAccessor` (NSViewRepresentable) used to get the `NSWindow` reference for configuration
- `WindowManager` (singleton) manages the window lifecycle, identifier-based deduplication, frame autosave

**2. Menu Bar (MenuBarExtra):**
- SwiftUI `MenuBarExtra` with `.menuBarExtraStyle(.menu)`
- Custom icon from asset catalog, sized to 22pt height
- Full control surface: model selection, AI enhancement toggle, prompt selection, provider/model switching, language, audio device, history, settings

**3. Recorder Overlay (NSPanel):**
Two variants, user-selectable:
- **Mini Recorder** (`MiniWindowManager` + `MiniRecorderPanel`): floating panel positioned on screen
- **Notch Recorder** (`NotchWindowManager` + `NotchRecorderPanel`): positioned at the notch area

Both use `NSPanel` subclasses (custom `NSWindow` subclass) hosted via `NSHostingController` wrapping SwiftUI views. Managed by `RecorderUIManager` which handles show/hide/toggle lifecycle.

### Activation Policy Switching

**File:** `VoiceInk/MenuBarManager.swift`

Uses `NSApplication.shared.setActivationPolicy()` to toggle between:
- `.regular` -- dock icon visible, standard app behavior
- `.accessory` -- menu bar only, no dock icon

Monitors `NSWindow.willCloseNotification` to switch back to `.accessory` when all windows close (if in menu-bar-only mode).

### Settings Window

Not a separate window -- it's a tab in the main `NavigationSplitView`. `ViewType` enum cases: Dashboard, Transcribe Audio, History, AI Models, Enhancement, Power Mode, Permissions, Audio Input, Dictionary, Settings, VoiceInk Pro.

### Patterns to Reimplement for PersonalScribe

- `WindowAccessor` NSViewRepresentable to bridge NSWindow from SwiftUI
- Singleton `WindowManager` for window deduplication and lifecycle
- `NSPanel` subclass for floating recorder overlays (not `NSWindow`)
- `RecorderUIManager` as intermediary between hotkey/UI and engine
- Activation policy switching for dock icon hide/show
- `@NSApplicationDelegateAdaptor` for AppKit lifecycle hooks
- Dependency injection via `@StateObject` + `.environmentObject()` chain

---

## 5. Dependency Usage

### KeyboardShortcuts (sindresorhus, v2.4.0)
**Files:** `VoiceInk/HotkeyManager.swift`, `VoiceInk/MiniRecorderShortcutManager.swift`, `VoiceInk/PowerMode/PowerModeShortcutManager.swift`

Used for custom keyboard shortcuts (when user selects "Custom" hotkey option). Named shortcuts defined as extensions on `KeyboardShortcuts.Name`. Uses both `onKeyDown` and `onKeyUp` callbacks for hybrid/push-to-talk modes. Also used for utility shortcuts: paste last transcription, paste last enhancement, retry, open history, quick-add dictionary.

The modifier key detection (right Option, right Command, Fn, etc.) is done via `NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged)` -- NOT KeyboardShortcuts. This is because KeyboardShortcuts doesn't support single modifier keys as shortcuts.

### Sparkle (v2.8.0)
**File:** `VoiceInk/VoiceInk.swift`

`SPUStandardUpdaterController` initialized with `startingUpdater: true`. Auto-check interval: 24 hours. `UpdaterViewModel` wraps it as an `@ObservableObject`. Silent background check on launch, manual check via menu bar.

### LaunchAtLogin (sindresorhus, LaunchAtLogin-Modern)
**File:** `VoiceInk/Views/MenuBarView.swift`

Simple toggle: `LaunchAtLogin.isEnabled`. Used as a binding in the menu bar view.

### SelectedTextKit (tisfeng, v2.6.2)
**File:** `VoiceInk/Services/SelectedTextService.swift`

Thin wrapper. Uses strategies `[.accessibility, .menuAction]` to get currently selected text. Used by `AIEnhancementService` to include selected text as context for AI enhancement.

### MediaRemoteAdapter (ejbills)
**File:** `VoiceInk/PlaybackController.swift`

Used to pause/resume media playback during recording. Listens for track info updates, pauses on recording start, resumes after recording ends (with configurable delay). Fallback: simulates hardware Play/Pause key via `NSEvent.otherEvent` with `NX_KEYTYPE_PLAY`.

### FluidAudio (FluidInference)
**File:** `VoiceInk/Transcription/Batch/FluidAudioTranscriptionService.swift`

Binary SPM package for Parakeet TDT ASR model. `AsrModels.downloadAndLoad(version:)` for download, `AsrModels.loadFromCache` for loading. `AsrManager` for transcription. `VadManager` for voice activity detection.

### Other Dependencies
- **Zip** (marmelroy, v2.1.2) -- unzipping Core ML model archives
- **swift-atomics** (apple, v1.3.0) -- `ManagedAtomic` for thread-safe download completion flags
- **AXSwift** (tisfeng, v0.3.6) -- accessibility API wrapper (used by SelectedTextKit)
- **KeySender** (jordanbaird, v0.0.5) -- not directly used in main source (possibly SelectedTextKit dependency)
- **LLMkit** (Beingpax) -- their own wrapper for LLM API calls (OpenAI, Anthropic compatible)

---

## 6. Project Structure

```
VoiceInk/
  VoiceInk.swift              -- @main App, all service initialization
  AppDelegate.swift            -- NSApplicationDelegate (file open handling)
  AppDefaults.swift            -- UserDefaults.register(defaults:)
  Recorder.swift               -- CoreAudio recording wrapper
  CoreAudioRecorder.swift      -- Low-level CoreAudio tap
  CursorPaster.swift           -- Clipboard paste + restore
  ClipboardManager.swift       -- NSPasteboard wrapper
  HotkeyManager.swift          -- Global hotkey handling
  MenuBarManager.swift         -- Dock/menu bar policy
  WindowManager.swift          -- Main window lifecycle
  HistoryWindowController.swift -- Separate history window
  MediaController.swift        -- System audio mute/unmute
  PlaybackController.swift     -- Media pause/resume
  SoundManager.swift           -- Start/stop/cancel sound effects

  PowerMode/
    PowerModeConfig.swift       -- Data model + PowerModeManager
    ActiveWindowService.swift   -- Frontmost app detection
    BrowserURLService.swift     -- Browser URL via AppleScript
    PowerModeSessionManager.swift -- State save/restore
    PowerModeStateProvider.swift  -- Protocol for engine bridging
    PowerModeShortcutManager.swift -- Per-config keyboard shortcuts
    PowerModeView.swift          -- Settings UI
    PowerModeConfigView.swift    -- Config editor UI
    PowerModePopover.swift       -- Menu bar popover
    PowerModeViewComponents.swift -- Shared UI components
    AppPicker.swift              -- App selection UI
    EmojiPickerView.swift / EmojiManager.swift -- Emoji selection

  Transcription/
    Core/
      VoiceInkEngine.swift           -- Central recording/transcription orchestrator
      VoiceInkEngine+Protocols.swift -- Protocol conformances
      TranscriptionModelManager.swift -- Unified model registry
      TranscriptionServiceRegistry.swift -- Service dispatch
      TranscriptionPipeline.swift    -- Post-recording pipeline
      TranscriptionSession.swift     -- Session protocol + implementations
      RecorderUIManager.swift        -- Recorder show/hide/toggle
      AudioFileProcessor.swift       -- Audio file processing
      RecordingState.swift           -- State enum
      VoiceInkEngineError.swift      -- Error types
      Whisper/
        LibWhisper.swift             -- whisper.cpp actor wrapper
        WhisperModelManager.swift    -- Download/load/delete whisper models
        WhisperPrompt.swift          -- Transcription prompt management
        VADModelManager.swift        -- VAD model from bundle
        WhisperModelWarmupCoordinator.swift
      FluidAudio/
        FluidAudioModelManager.swift -- Parakeet model lifecycle
    Processing/
      TranscriptionOutputFilter.swift -- Hallucination/bracket removal
      FillerWordManager.swift        -- Filler word list + removal
      WhisperTextFormatter.swift     -- Paragraph chunking (NLTokenizer)
      WordReplacementService.swift   -- User-defined word replacements
    Streaming/
      StreamingTranscriptionService.swift -- WebSocket streaming lifecycle
      StreamingTranscriptionProvider.swift -- Provider protocol
      DeepgramStreamingProvider.swift
      ElevenLabsStreamingProvider.swift
      FluidAudioStreamingProvider.swift
      MistralStreamingProvider.swift
      SonioxStreamingProvider.swift
      SpeechmaticsStreamingProvider.swift
      WordAgreementEngine.swift
    Batch/
      LocalTranscriptionService.swift     -- whisper.cpp batch
      FluidAudioTranscriptionService.swift -- Parakeet batch
      CloudTranscriptionService.swift     -- REST API batch
      NativeAppleTranscriptionService.swift -- macOS 26 Speech
      OpenAICompatibleTranscriptionService.swift
      CustomModelManager.swift

  Services/
    AIEnhancement/
      AIEnhancementService.swift    -- AI post-processing orchestrator
      AIService.swift               -- LLM provider management
      AIEnhancementOutputFilter.swift
      LocalCLIService.swift         -- Local CLI model support
      ReasoningConfig.swift         -- Per-model reasoning parameters
    APIKeyManager.swift / KeychainService.swift -- Keychain storage
    AudioDeviceManager.swift / AudioDeviceConfiguration.swift
    ScreenCaptureService.swift      -- Screen OCR via ScreenCaptureKit + Vision
    SelectedTextService.swift       -- Selected text via SelectedTextKit
    CustomVocabularyService.swift   -- Custom vocabulary for prompts
    AutoLearnVocabularyService.swift -- Auto-learn from corrections
    PromptDetectionService.swift    -- Trigger word detection
    ModelPrewarmService.swift       -- Model warmup on wake
    WordDiffEngine.swift / WordCounter.swift
    DictionaryService.swift / DictionaryMigrationService.swift
    ImportExportService.swift / VoiceInkCSVExportService.swift
    OllamaService.swift             -- Ollama local LLM
    LastTranscriptionService.swift
    UserDefaultsManager.swift
    LicenseManager.swift / Obfuscator.swift
    TranscriptionAutoCleanupService.swift
    AudioFileTranscriptionManager.swift / AudioFileTranscriptionService.swift
    AnnouncementsService.swift
    LogExporter.swift
    SystemInfoService.swift / SystemArchitecture.swift
    SupportedMedia.swift
    LocalModelProvider.swift
    PolarService.swift
    EnhancementShortcutSettings.swift

  Models/
    TranscriptionModel.swift       -- Protocol + concrete types
    PredefinedModels.swift         -- Hardcoded model catalog
    Transcription.swift            -- SwiftData @Model
    CustomPrompt.swift             -- Prompt data model
    PredefinedPrompts.swift / PromptTemplates.swift / AIPrompts.swift
    VocabularyWord.swift           -- SwiftData @Model
    WordReplacement.swift          -- SwiftData @Model
    AudioFileQueueItem.swift
    LicenseViewModel.swift

  Views/ (large -- many specialized views)
    ContentView.swift              -- NavigationSplitView main layout
    MenuBarView.swift              -- Menu bar dropdown
    Recorder/ (MiniRecorderView, NotchRecorderView, AudioVisualizerView, etc.)
    Settings/ (SettingsView, AudioInputSettingsView, etc.)
    AI Models/ (ModelManagementView, etc.)
    History/ (TranscriptionHistoryView, etc.)
    Metrics/ (MetricsView, dashboards)
    Onboarding/ (OnboardingView, permissions, model download)
    Dictionary/ (vocabulary management)
    Components/ Common/

  AppIntents/ (Siri Shortcuts integration)
  Notifications/ (In-app notifications, announcements)
  Resources/ (sounds, bundled models)

VoiceInkTests/ (1 file -- minimal)
VoiceInkUITests/ (2 files -- minimal)
```

### Build Configuration

- **Xcode project** (not SPM Package.swift)
- **whisper.cpp** built as XCFramework via `build-xcframework.sh`, linked as binary framework
- **FluidAudio** imported via SPM (binary package)
- **LocalBuild.xcconfig** for unsigned local builds with `LOCAL_BUILD` compilation flag
- **Makefile** automates: clone whisper.cpp, build XCFramework, build app
- **SwiftData** with two stores: `default.store` (transcriptions) and `dictionary.store` (vocabulary, with iCloud sync for non-local builds)
- **#if LOCAL_BUILD** conditional: disables CloudKit dictionary sync
- **Entitlements**: separate `.entitlements` and `.local.entitlements` files

### Test Structure

Minimal -- only boilerplate test files. No meaningful test coverage visible in the repo.

---

## 7. Model Management

### Whisper Models

**File:** `VoiceInk/Transcription/Core/Whisper/WhisperModelManager.swift`

- **Storage:** `~/Library/Application Support/com.prakashjoshipax.VoiceInk/WhisperModels/`
- **Format:** `.bin` files from HuggingFace (`ggerganov/whisper.cpp`)
- **Download:** Two-phase -- main model + Core ML encoder (for non-quantized models)
- **Progress tracking:** `[String: Double]` dictionary keyed by `modelName + "_main"` and `modelName + "_coreml"`, throttled to 0.5s / 1% updates
- **Import:** Users can import local `.bin` files (copied to models directory)
- **Selection:** Stored in `UserDefaults("CurrentTranscriptionModel")` by name
- **Loading:** Lazy -- loaded on first recording, released after transcription completes
- **Warmup:** Non-quantized models get a warmup transcription after download via `WhisperModelWarmupCoordinator`

### FluidAudio/Parakeet Models

**File:** `VoiceInk/Transcription/Core/FluidAudio/FluidAudioModelManager.swift`

- **Download:** `AsrModels.downloadAndLoad(version:)` -- managed by FluidAudio SDK
- **Cache location:** Managed by `AsrModels.defaultCacheDirectory(for:)`
- **State tracking:** `UserDefaults("ParakeetModelDownloaded_<name>")` -- boolean flags
- **Progress:** Simulated with timer (SDK doesn't provide real progress)
- **Model versions:** v2 and v3 of parakeet-tdt-0.6b

### Cloud Models

No download needed -- just API key validation. API keys stored in Keychain via `APIKeyManager`/`KeychainService`. Custom models also store endpoint URL and model name.

### Patterns to Reimplement for PersonalScribe

- Two-phase download (model + accelerator) with combined progress
- Application Support directory for model storage
- Lazy model loading with explicit cleanup after use
- Model warmup on download/wake for ANE compilation
- UserDefaults-based model selection (by name, not UUID)
- Import flow for user-provided model files

---

## 8. Post-Processing Pipeline

### TranscriptionPipeline

**File:** `VoiceInk/Transcription/Core/TranscriptionPipeline.swift`

Full pipeline order:
1. **Transcribe** (via session or service registry)
2. **Output filter** (`TranscriptionOutputFilter.filter()`)
3. **Trim whitespace**
4. **Text formatting** (`WhisperTextFormatter.format()`) -- if enabled
5. **Word replacement** (`WordReplacementService.shared.applyReplacements()`)
6. **Prompt detection** (`PromptDetectionService.analyzeText()`) -- detects trigger words
7. **AI enhancement** (`AIEnhancementService.enhance()`) -- if enabled and configured
8. **Save** to SwiftData
9. **Paste** via `CursorPaster.pasteAtCursor()`
10. **Auto-send** keystroke if Power Mode config specifies
11. **Restore** prompt detection state
12. **Dismiss** recorder
13. **Begin** auto-learn vocabulary monitoring

### Output Filter

**File:** `VoiceInk/Transcription/Processing/TranscriptionOutputFilter.swift`

Removes:
- XML/HTML tag blocks: `<TAG>...</TAG>`
- Bracketed hallucinations: `[...]`, `(...)`, `{...}`
- Filler words (if enabled): configurable list, removed with word-boundary regex + trailing punctuation
- Multiple whitespace collapsed to single space

### Text Formatting

**File:** `VoiceInk/Transcription/Processing/WhisperTextFormatter.swift`

Chunks text into paragraphs (separated by `\n\n`) using NLTokenizer:
- Target: 50 words per chunk
- Max: 4 significant sentences per chunk (sentences with >= 4 words)
- Language auto-detected via `NLLanguageRecognizer`

### Word Replacement

**File:** `VoiceInk/Transcription/Processing/WordReplacementService.swift`

- SwiftData-backed `WordReplacement` entries (with `isEnabled` flag)
- Supports comma-separated originals (e.g., "colour, color" -> "color")
- Case-insensitive matching
- Word-boundary aware for Latin scripts, substring replacement for CJK/Thai (detects script via Unicode ranges)

### Filler Word Removal

**File:** `VoiceInk/Transcription/Processing/FillerWordManager.swift`

Default list: `uh, um, uhm, umm, uhh, uhhh, hmm, hm, mmm, mm, mh, ehh`. User-customizable. Removed with word-boundary regex that also strips trailing comma/period.

### Prompt Detection (Trigger Words)

**File:** `VoiceInk/Services/PromptDetectionService.swift`

Scans transcribed text for trigger words defined on AI prompts. If found:
1. Strips the trigger word from the text (leading and/or trailing)
2. Temporarily enables AI enhancement with the matched prompt
3. After paste, restores original enhancement state

Trigger word detection handles both leading and trailing positions, strips punctuation, and re-capitalizes the remaining text.

### AI Enhancement

**File:** `VoiceInk/Services/AIEnhancement/AIEnhancementService.swift`

Context assembly for the LLM system prompt:
1. **Selected text** (via `SelectedTextService` using accessibility API)
2. **Clipboard content** (captured at recording start)
3. **Screen capture OCR** (via `ScreenCaptureService` using ScreenCaptureKit + Vision framework)
4. **Custom vocabulary** (from SwiftData)
5. **Active prompt template**

Request format: system prompt with context sections wrapped in XML tags (`<CURRENTLY_SELECTED_TEXT>`, `<CLIPBOARD_CONTEXT>`, `<CURRENT_WINDOW_CONTEXT>`, `<CUSTOM_VOCABULARY>`), user message wraps transcript in `<TRANSCRIPT>` tags.

Supports providers: Anthropic (via custom client), OpenAI-compatible (via LLMkit), Ollama (local), Local CLI.

Retry with exponential backoff for network/server/rate-limit errors. Configurable timeout (default 7s).

### Screen Capture for Context

**File:** `VoiceInk/Services/ScreenCaptureService.swift`

Uses ScreenCaptureKit to capture the active window, then Vision framework (`VNRecognizeTextRequest`) for OCR. Captures at 2x resolution. Includes window title and app name in context.

### Patterns to Reimplement for PersonalScribe

- Pipeline pattern with ordered processing stages and cancellation checks between stages
- Hallucination removal (bracket/tag stripping)
- NLP-based text chunking into paragraphs
- Script-aware word replacement (Latin vs CJK word boundaries)
- Trigger word detection for automatic prompt switching
- Multi-source context assembly (selected text + clipboard + screen OCR + vocabulary)
- XML-tagged context sections in LLM prompts
- Retry with exponential backoff
- Screen OCR via ScreenCaptureKit + Vision (no external dependencies)

---

## 9. Key Architectural Patterns Summary

### What VoiceInk Does Well

1. **Protocol-based engine abstraction** -- `TranscriptionModel`, `TranscriptionService`, `TranscriptionSession`, `PowerModeStateProvider` allow clean separation between the engine core and specific implementations.

2. **Session lifecycle** -- The `TranscriptionSession` protocol with prepare/transcribe/cancel and the streaming-with-batch-fallback pattern is well-designed for unreliable network conditions.

3. **Power Mode session persistence** -- Serializing the baseline state to UserDefaults for crash recovery is a practical pattern for a menu bar app that runs continuously.

4. **Clipboard save/restore** -- Multi-type clipboard preservation (not just strings) with transient pasteboard type signaling is thorough.

5. **Context-aware AI enhancement** -- Assembling selected text + clipboard + screen OCR + vocabulary into structured XML context for the LLM prompt is a powerful pattern.

6. **Model pre-warming** -- Proactively loading models on wake/launch to avoid cold-start latency during first dictation.

### What We Should Do Differently for PersonalScribe

1. **Reduce singleton usage** -- VoiceInk uses many `.shared` singletons (PowerModeManager, ActiveWindowService, FillerWordManager, etc.). We should prefer dependency injection.

2. **Better state management** -- VoiceInk uses `UserDefaults` extensively for state that could benefit from a more structured store. Consider a dedicated settings/config layer.

3. **Test coverage** -- VoiceInk has essentially zero tests. We should build with testability in mind from the start, especially for the pipeline stages and Power Mode matching logic.

4. **Notification-based communication** -- VoiceInk uses `NotificationCenter` heavily for inter-component communication. We should prefer Combine publishers, async streams, or explicit delegate protocols.

5. **Error handling** -- VoiceInk silently swallows many errors. We should have structured error propagation and user-facing error reporting.

6. **Modular build** -- VoiceInk is a monolithic Xcode project. We could benefit from SPM modules for testing and reuse (engine, models, UI).
