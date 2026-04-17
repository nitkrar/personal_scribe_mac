# Scribe Deep-Dive: Architecture & Implementation Analysis

**Source**: https://github.com/mariov96/scribe (cloned to /tmp/scribe_exploration)
**Date**: 2026-04-15
**Purpose**: Extract patterns worth adapting for PersonalScribe (native Mac voice dictation app in Swift)

---

## 1. High-Level Architecture

Scribe is a Python/Windows voice automation platform built on:
- **faster-whisper** (CTranslate2-based Whisper) for transcription
- **PyQt5 + QFluentWidgets** for UI
- **sounddevice** (PortAudio) for audio capture
- **keyboard + pynput** for global hotkeys
- **SQLite + FTS5** for conversation history
- **Pydantic** for config validation
- **YAML** for config persistence

### Core data flow (from `src/scribe/app.py`):
```
User presses hotkey
  -> HotkeyManager emits signal (keyboard thread -> Qt main thread via QueuedConnection)
  -> AudioRecorder captures mic via sounddevice InputStream
  -> TranscriptionWorker (QThread) runs faster-whisper
  -> TextFormatter applies AI cleanup (filler removal, voice commands, smart punctuation)
  -> _process_as_command() checks plugin registry for voice commands
  -> If dictation: paste text back to originating app via clipboard + Ctrl+V
  -> ValueCalculator records analytics
  -> Database stores history with FTS5 search
```

### Threading model (documented extensively in `app.py` docstring):
1. **Main/GUI thread** - Qt event loop, all UI updates
2. **Keyboard thread** - global hotkey listener (keyboard library)
3. **Audio thread** - PortAudio callback (sounddevice)
4. **Worker thread** - QThread for transcription

**Key safety pattern**: Never call UI from non-main threads. Use `QTimer.singleShot(0, ...)` to defer to main thread, and `Qt.QueuedConnection` for cross-thread signals. Audio callback must NEVER emit Qt signals directly (causes segfault).

**Swift adaptation**: Use `@MainActor` and `Task { @MainActor in ... }` for the same pattern. Audio capture on a dedicated `DispatchQueue`, transcription on a background task.

---

## 2. Learning/Memory System

### Current state: Design docs only, not yet implemented in code

The learning system is documented in two design documents but the actual implementation consists only of:
1. **TextFormatter** (`src/scribe/core/text_formatter.py`) - rule-based, no learning
2. **ValueCalculator** (`src/scribe/analytics/value_calculator.py`) - records metrics, no adaptation
3. **DatabaseManager** (`src/scribe/core/database.py`) - stores transcription history, no ML

### What IS implemented: TextFormatter (rule-based cleanup)

File: `src/scribe/core/text_formatter.py`

```python
class TextFormatter:
    _FILLER_WORDS = {"um", "uh", "erm", "hmm", "like", "kind of", "sort of"}

    _VOICE_REPLACEMENTS = [
        (r"\bnew paragraph\b", "\n\n"),
        (r"\bnew line\b", "\n"),
        (r"\bbullet point\b", "\n- "),
        # ...
    ]

    _NUMBER_WORDS = {"zero": "0", "one": "1", ...}

    _QUESTION_STARTERS = ("who", "what", "when", "where", "why", "how", ...)

    def format_text(self, text):
        if config.enable_ai_cleanup:    processed = self._remove_fillers(processed)
        if config.enable_voice_commands: processed = self._apply_voice_commands(processed)
        if config.enable_number_conversion: processed = self._convert_numbers(processed)
        if config.enable_smart_punctuation: processed = self._smart_punctuation(processed)
        # ...
```

This is entirely regex-based. No NLP pipeline. No fine-tuning. No prompt-based LLM cleanup.

### What IS designed but NOT built: PersonalVoiceModel

File: `docs/PERSONAL_VOICE_MODEL.md`

The design describes a 4-phase system:
1. **Passive Learning** - Store all transcriptions with before/after edits; track user corrections; learn which AI suggestions are kept vs rejected
2. **Active Training** - Style samples ("Read these 5 sentences"); preference feedback; manual corrections
3. **Contextual Adaptation** - Situation detection (formal vs casual); audience awareness
4. **Voice Profile** - JSON structure storing vocabulary frequency, syntax patterns, tonality scores, filler patterns

Key data structure from the design doc:
```json
{
  "voice_profile": {
    "vocabulary": {
      "frequent_words": {"probably": 0.15, "actually": 0.12},
      "preferred_synonyms": {"big": "huge", "good": "solid"}
    },
    "syntax_patterns": {
      "sentence_starters": ["So", "I think", "Honestly"],
      "average_sentence_length": 18
    },
    "tonality": {
      "formality_level": 0.4,
      "technical_level": 0.7,
      "confidence_level": 0.8
    }
  }
}
```

The design envisions prompt-based AI cleanup using the voice profile to generate personalized system prompts:
```python
def generate_personalized_prompt(self, text, voice_profile):
    if voice_profile.uses_word_frequently("probably"):
        style_instructions.append("Keep words like 'probably'...")
    if voice_profile.formality_level < 0.5:
        style_instructions.append("Maintain casual tone")
```

### Correction detection (designed, not implemented)

From the design doc, correction detection would work by:
- Comparing `original_text` -> `ai_edited` -> `user_final`
- Tracking which AI edits the user keeps vs reverts
- Building a profile of preserved personal vocabulary

### Gemini API integration (partial implementation)

File: `src/scribe/core/scf_cacher.py`

A `ScfCacher` class exists that wraps Google's Gemini API with cached content support. This is infrastructure for future LLM-based cleanup but is not wired into the transcription pipeline.

```python
class ScfCacher:
    def __init__(self, api_key):
        genai.configure(api_key=api_key)
        self.model_id = "gemini-1.5-pro-latest"

    def create_cache(self, content, display_name, ttl="3600s"):
        cache = genai.caching.CachedContent.create(
            model=self.model_id,
            contents=[content_types.to_content(content)],
            display_name=display_name,
            ttl=ttl,
        )

    def generate_with_cache(self, cache_name, user_prompt):
        response = self.model.generate_content(
            contents=user_prompt,
            cached_content=cache_name
        )
```

### Evolutionary AI analysis

File: `docs/EVOLUTIONARY_AI_ANALYSIS.md`

Scribe explicitly evaluated and rejected complex ML approaches:
- REJECTED: Full evolutionary algorithms (DEAP) - "over-engineering"
- REJECTED: AutoML/meta-learning - "unnecessary complexity"
- ADOPTED (design only): A/B testing for feature effectiveness
- ADOPTED (design only): Personal data learning via VoiceProfile
- ADOPTED (design only): Milestone-based feature unlocking (GrowthManager)

**Key takeaway for PersonalScribe**: Scribe's learning system is entirely aspirational. The actual implementation is pure regex. There is real opportunity for PersonalScribe to implement what Scribe only designed -- particularly the correction-tracking feedback loop and profile-guided LLM cleanup. The Gemini cached content approach is interesting for reducing API costs when sending large voice profiles as context.

---

## 3. Voice Commands & Plugin System

### BasePlugin class (`src/scribe/plugins/base.py`)

```python
class BasePlugin(ABC):
    name: str = "unnamed_plugin"
    version: str = "0.0.0"
    description: str = ""
    author: str = ""
    api_version: str = "2.0"

    @abstractmethod
    def commands(self) -> List[CommandDefinition]:
        """Return list of commands this plugin handles."""

    @abstractmethod
    def initialize(self, config: Dict[str, Any]) -> bool:
        """Initialize with configuration. Return True if successful."""

    def shutdown(self):
        """Optional cleanup on unload."""

    def validate(self) -> tuple[bool, str]:
        """Validate plugin structure. Checks API version, command definitions."""

    def get_metadata(self) -> Dict[str, Any]:
        """Return plugin info dict with commands."""
```

### CommandDefinition (`src/scribe/plugins/base.py`)

```python
@dataclass
class CommandDefinition:
    patterns: List[str]        # e.g., ["switch to {app}", "open {app}"]
    handler: Callable          # Method to call when matched
    examples: List[str]        # Help text examples
    description: str = ""      # Human-readable description
```

### Pattern matching vs regular dictation (`src/scribe/app.py`)

The command detection happens in `_process_as_command()`. Every transcription result is checked against ALL registered command patterns before being treated as regular dictation.

The pattern matching engine (`_pattern_matches()`) uses template-based regex:
- `{placeholder}` tokens become regex capture groups
- Last placeholder is greedy (`.+` to capture multi-word values)
- Middle placeholders are non-greedy (`\S+` for single words)
- Matching is case-insensitive with `\b` word boundaries

```python
def _pattern_matches(self, text: str, pattern: str) -> Tuple[bool, Dict[str, str]]:
    # "switch to {app}" becomes regex:
    # \bswitch\s+to\s+(?P<app>.+)\b
    #
    # "open {file} in {app}" becomes:
    # \bopen\s+(?P<file>\S+)\s+in\s+(?P<app>.+)\b
```

This approach has a design limitation: there is no intent classification or fuzzy matching. If someone says "can you switch to chrome please", it won't match "switch to {app}" because of the prefix/suffix words. There's a TODO in the code: "TODO: Improve with intent classification".

### Plugin Registry (`src/scribe/plugins/registry.py`)

```python
class PluginRegistry:
    _plugins: Dict[str, BasePlugin]              # name -> plugin instance
    _commands: Dict[str, List[RegisteredCommand]] # pattern -> commands
    _plugin_configs: Dict[str, Dict[str, Any]]    # name -> config

    def register_plugin(plugin, config) -> bool:
        # 1. Validate via plugin.validate()
        # 2. Check for duplicates
        # 3. Initialize via plugin.initialize(config)
        # 4. Register all command patterns

    def execute_command(pattern, **kwargs):
        # Find first matching RegisteredCommand, execute its handler
        # TODO: priority system for overlapping patterns

    def reload_plugin(name):
        # Unregister, re-instantiate, re-register (for development)
```

### Plugin loader (`src/scribe/plugins/loader.py`)

Dynamic discovery: scans directories for `*/plugin.py` files, imports them, finds `BasePlugin` subclasses, instantiates them.

```python
def load_plugins(plugin_dirs: List[Path]) -> List[BasePlugin]:
    for plugin_dir in plugin_dirs:
        for module_path in plugin_dir.glob("*/plugin.py"):
            module = importlib.import_module(module_name)
            for name, obj in inspect.getmembers(module):
                if issubclass(obj, BasePlugin) and obj is not BasePlugin:
                    loaded_plugins.append(obj())
                    break  # One plugin per plugin.py
```

### Existing plugins

1. **WindowManager** (`src/scribe/plugins/window_manager/plugin.py`) - Voice control of windows via `pygetwindow`. Commands: switch to, minimize, maximize, close, list windows. Uses app_shortcuts config for aliases ("chrome" -> "Google Chrome").

2. **MeetingNoteTaker** (`src/scribe/plugins/meeting/`) - Records meeting audio, stores metadata as JSON per meeting directory, with planned (but unimplemented) transcription integration.

### Swift adaptation notes

The plugin system is clean and worth adapting. For Swift:
- Use a `Protocol` instead of ABC: `protocol ScribePlugin`
- `CommandDefinition` maps well to a Swift struct
- Pattern matching with `{placeholder}` -> NSRegularExpression with named capture groups
- Plugin discovery could use Swift Package Manager plugins or a simple directory scan
- Consider adding intent classification (even a simple keyword prefix check) to avoid the strict-match limitation

---

## 4. Memory/Context System

### Conversation context capture (`src/scribe/app.py`)

Before each recording, Scribe captures the active window context:

```python
def _capture_context(self) -> Dict[str, Optional[str]]:
    context = {"application": None, "window_title": None, "window_handle": None}

    # Win32 API: GetForegroundWindow()
    handle = win32gui.GetForegroundWindow()
    context["window_handle"] = int(handle)

    # pygetwindow fallback
    window = gw.getActiveWindow()
    context["window_title"] = window.title
    context["application"] = self._extract_application_name(title)
```

This context is:
1. Passed to `ValueCalculator.record_transcription()` as metadata
2. Used to return text to the originating app via clipboard paste
3. Stored in the history entry shown in the UI

### Database schema (`src/scribe/core/database.py`)

SQLite database at `~/.scribe/data/scribe.db`:

```sql
CREATE TABLE transcriptions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME NOT NULL,
    text TEXT NOT NULL,
    application TEXT,
    window_title TEXT,
    audio_duration REAL,
    word_count INTEGER,
    character_count INTEGER,
    confidence REAL,
    language TEXT,
    used_plugin TEXT,
    ai_formatted BOOLEAN,
    raw_text TEXT,
    quality_rating INTEGER,
    quality_feedback TEXT,
    audio_file TEXT
);

-- Full-text search via FTS5
CREATE VIRTUAL TABLE transcriptions_fts USING fts5(
    text, application, window_title,
    content='transcriptions', content_rowid='id'
);
```

FTS5 triggers keep the search index in sync on INSERT/UPDATE/DELETE. Search is exposed via:
```python
def search_transcriptions(self, search_term: str):
    cursor.execute(
        "SELECT * FROM transcriptions_fts WHERE transcriptions_fts MATCH ? ORDER BY rank",
        (search_term,)
    )
```

### Voice profile persistence (designed, not implemented)

The design doc (`docs/PERSONAL_VOICE_MODEL.md`) specifies a JSON-based voice profile stored locally, but no code exists for this. The design envisions:
- Vocabulary frequency maps
- Preferred synonym mappings
- Syntax pattern libraries
- Formality/confidence/enthusiasm scores (0-1 floats)
- Context-specific sub-profiles (meeting vs email vs casual)

### Meeting storage (`src/scribe/plugins/meeting/models.py`)

Each meeting is a directory under `~/.scribe/meetings/{uuid}/`:
- `metadata.json` - title, date, duration, status, transcript
- `audio.wav` - raw recording

### Swift adaptation notes

For PersonalScribe:
- Use `NSWorkspace.shared.frontmostApplication` and `AXUIElement` for context capture on macOS
- SwiftData or GRDB for SQLite with FTS5 (Core Data does not support FTS5 natively)
- The voice profile JSON structure is a good starting point -- adapt to `Codable` structs
- Consider storing voice profiles in the app's Application Support directory
- The FTS5 approach for searching past transcriptions is well-suited to macOS

---

## 5. Analytics System

### ValueCalculator (`src/scribe/analytics/value_calculator.py`)

This is the most complete module in the codebase. Key metrics:

**Constants:**
```python
AVERAGE_TYPING_SPEED = 40   # WPM (conservative)
AVERAGE_SPEAKING_SPEED = 150  # WPM
COMMAND_VALUE_MULTIPLIER = 3.0  # Commands save 3x more
```

**Time saved calculation:**
```python
def calculate_time_saved(self, word_count, audio_duration, was_command=False):
    typing_time = (word_count / AVERAGE_TYPING_SPEED) * 60  # seconds
    speaking_time = audio_duration
    time_saved = typing_time - speaking_time
    if was_command:
        time_saved *= COMMAND_VALUE_MULTIPLIER
    return max(0, time_saved)
```

**Productivity multiplier:**
```python
def calculate_productivity_multiplier(self, summary):
    typing_time = (summary.total_words / AVERAGE_TYPING_SPEED) * 60
    actual_time = summary.total_audio_duration + summary.total_transcription_time
    return typing_time / actual_time  # e.g., 2.5x faster
```

**Accuracy score:**
```python
def calculate_accuracy_score(self, transcriptions):
    total_words = sum(t.word_count for t in transcriptions)
    total_corrections = sum(t.corrections_made for t in transcriptions)
    return 1.0 - (total_corrections / total_words)
```

**Session persistence:** Saves to `data/analytics/session_TIMESTAMP.json` with structure:
```json
{
  "session": {"start": "...", "end": "...", "duration_minutes": 45.2},
  "transcription": {"total_count": 23, "total_words": 1450, "audio_duration_seconds": 120},
  "commands": {"total_count": 5, "successful": 4, "success_rate": 0.8},
  "value": {"time_saved_seconds": 180, "productivity_multiplier": 2.1, "accuracy_score": 0.95},
  "feature_usage": {"window_manager": 3, "meeting": 2}
}
```

**Lifetime aggregation:** Scans all `session_*.json` files to compute total words, total time saved, etc.

### Insights UI (`src/scribe/ui_fluent/pages/insights.py`)

Generates insight cards dynamically from ValueCalculator data:
- "Session Activity" - transcription count and word total
- "Typing Saved" - minutes saved based on 40 WPM typing speed
- "Productivity Boost" - Nx multiplier
- "Transcription Quality" - accuracy percentage
- "Voice Commands" - command count and success rate

Regenerates on every new transcription event for live updates.

### Data structures

```python
@dataclass
class TranscriptionMetrics:
    timestamp: datetime
    audio_duration: float
    word_count: int
    character_count: int
    transcription_time: float
    ai_enhancement_time: float = 0.0
    corrections_made: int = 0
    was_command: bool = False
    confidence: Optional[float] = None
    language: Optional[str] = None
    application: Optional[str] = None
    window_title: Optional[str] = None
    text: str = ""

@dataclass
class SessionSummary:
    start_time: datetime
    end_time: datetime
    total_transcriptions: int = 0
    total_words: int = 0
    total_audio_duration: float = 0.0
    time_saved_vs_typing: float = 0.0
    productivity_multiplier: float = 1.0
    accuracy_score: float = 0.0
    feature_usage: Dict[str, int] = field(default_factory=dict)
```

### Swift adaptation notes

The analytics system is the most directly portable part of Scribe:
- The time-saved formula is elegant and simple (typing_time - speaking_time)
- The 40 WPM baseline is conservative and defensible
- Session JSON persistence maps cleanly to `Codable` + `FileManager`
- Consider using CloudKit for cross-device lifetime stats on macOS/iOS
- The insights UI pattern (generate cards from summary data) works well with SwiftUI

---

## 6. Plugin Architecture Extensibility

### API surface for plugin authors

A plugin author needs to:
1. Create a directory under `plugins/` with `__init__.py` and `plugin.py`
2. Subclass `BasePlugin`
3. Implement `commands()` returning `List[CommandDefinition]`
4. Implement `initialize(config)` returning `bool`
5. Optionally implement `shutdown()` and `validate()`

### Configuration per plugin

Plugin-specific config lives in the main YAML under `plugins.plugin_config`:
```yaml
plugins:
  enabled_plugins: ["window_manager"]
  plugin_config:
    window_manager:
      app_shortcuts:
        chrome: "Google Chrome"
        code: "Visual Studio Code"
```

Accessed via `ConfigManager.get_plugin_config("window_manager")`.

### Hot reload support

```python
def reload_plugin(self, plugin_name):
    config = self._plugin_configs.get(plugin_name, {})
    plugin_class = type(self._plugins[plugin_name])
    self.unregister_plugin(plugin_name)
    new_plugin = plugin_class()
    self.register_plugin(new_plugin, config)
```

### Architecture decision rationale (from `docs/PLUGIN_ARCHITECTURES.md`)

Scribe evaluated three approaches:
1. **Class-based inheritance** (chosen) - ABC enforces contract at import time, 1-5ms overhead
2. **Decorator-based** (rejected) - magic behavior, runtime errors, 5-15ms overhead
3. **Protocol-based** (rejected for now) - less familiar to contributors

Decision factors: <100ms command execution requirement, new-contributor friendliness, IDE autocomplete support.

### Limitations

- No plugin dependency management
- No plugin marketplace/discovery
- No inter-plugin communication
- Command priority system is a TODO
- Pattern matching is strict (no fuzzy/intent-based)
- Only one plugin loaded per `plugin.py` file

### Swift adaptation notes

For PersonalScribe:
- Swift protocols are the natural equivalent of Python ABCs
- Consider using Swift Package Manager for plugin distribution
- The `CommandDefinition` pattern with `{placeholder}` templates is clean and reusable
- Add a `priority: Int` field to CommandDefinition for conflict resolution
- Consider adding an `IntentClassifier` layer between transcription and command matching to handle natural language variations
- The hot-reload pattern maps to Swift's dynamic library loading, but is likely unnecessary for a compiled Mac app -- instead, use a configuration-driven approach

---

## 7. Audio Pipeline Details

### Audio capture (`src/scribe/core/audio_recorder.py`)

- Uses `sounddevice.InputStream` with callback
- 16kHz mono int16 (optimal for Whisper)
- Audio chunks accumulated in `self.audio_data: List[np.ndarray]`
- VU meter via RMS computation in callback (level emitted via QTimer, NOT from audio thread)
- 2-minute safety limit on recording length
- Saves debug recordings to `data/audio/` with auto-cleanup (5-day retention, 100MB cap)
- Device validation via `can_open()` probe (opens/starts/stops/closes stream)

### Audio preprocessing (`src/scribe/core/transcription_engine.py`)

```python
def _preprocess_audio(self, wav_path):
    # 1. Noise gate: compute short-time energy envelope, zero out below threshold
    # 2. Optional VAD trim via webrtcvad (30ms frames, configurable aggressiveness 0-3)
    # 3. Optional level normalization to target dBFS with soft limiter (tanh)
```

### Transcription parameters

```python
transcribe_params = {
    "beam_size": 1,          # Greedy decoding (5x speed boost over beam_size=5)
    "best_of": 1,            # Single pass
    "word_timestamps": False, # Disabled for speed
    "condition_on_previous_text": False,  # Better for short clips
    "language": "en",        # Pre-specified (skip detection)
    "vad_filter": True/False, # Requires onnxruntime
}
```

### Hotkey system (`src/scribe/core/hotkey_manager.py`)

Dual-mode recording:
- **Hold mode**: Hold hotkey > 0.25s, release to stop
- **Toggle mode**: Quick press (<0.25s) starts recording, second press stops
- Uses both `keyboard` library and `pynput` as fallback (for non-admin Windows)
- WSL support via X11 key monitoring
- Debounce: combo state tracking prevents duplicate triggers

### Swift adaptation notes

- Use `AVAudioEngine` with `installTap(onBus:)` for audio capture on macOS
- Apple's built-in Speech framework or whisper.cpp for on-device transcription
- `CGEvent.tapCreate` or `NSEvent.addGlobalMonitorForEvents` for global hotkeys on macOS
- The hold-vs-toggle logic from `_on_hotkey_down`/`_on_hotkey_up` is directly portable
- Consider using Apple's Voice Activity Detection from the Speech framework instead of webrtcvad

---

## 8. Configuration System

### Pydantic models (`src/scribe/config/models.py`)

Hierarchical config with validation:

```python
class AppConfig(BaseModel):
    version: str = "2.0.0"
    profile_name: str = "default"
    audio: AudioConfig          # device_id, sample_rate, noise_gate_db, VAD settings
    hotkey: HotkeyConfig        # activation_key, recording_mode
    whisper: WhisperConfig      # model, device, compute_type, API settings
    ai_formatting: AIFormattingConfig  # cleanup toggles
    post_processing: PostProcessingConfig  # paste mode, trailing space, etc.
    plugins: PluginConfig       # enabled list + per-plugin config
    ui: UIConfig                # theme, tray, minimize behavior
```

Key features:
- `validate_assignment = True` - validates on field write
- `extra = "forbid"` - errors on unknown fields
- Field validators (e.g., hotkey format validation)
- Type-safe Literal unions for model names, recording modes, etc.

### ConfigManager (`src/scribe/config/config_manager.py`)

- YAML persistence with profile support (multiple `.yaml` files in `config/`)
- Qt signal emissions on config changes: `config_changed(section_name)`
- Live reload: changing `whisper.model` triggers debounced engine reload
- Profile switching, creation, deletion

### Swift adaptation notes

- Equivalent: `Codable` structs with `@AppStorage` or a custom `UserDefaults`-backed manager
- For validation, use Swift property wrappers with `willSet` checks
- The profile system (multiple YAML files) maps to named `UserDefaults` suites or JSON files in Application Support
- The signal-based config change notification maps to Combine's `@Published` properties or SwiftUI's `@Observable`

---

## 9. Text Output / Injection System

### Smart formatting (`src/scribe/app.py`)

Before pasting, Scribe applies:
1. **Leading space** - adds ` ` before text (assumes appending to existing text)
2. **Capitalize first** - respects leading quotes/brackets
3. **Ensure period** - optional sentence-ending punctuation
4. **Trailing space** - after sentence-ending punctuation

### Text injection modes

```python
auto_insert_mode: "paste" | "type" | "both"
```

- **paste**: `pyperclip.copy(text)` then `pyautogui.hotkey('ctrl', 'v')` with 200ms delay
- **type**: `pyautogui.typewrite(text, interval=0.002)` - keystroke simulation
- **both**: try paste, fall back to type

### Window restoration

1. Capture foreground window handle before recording
2. After transcription, restore via `win32gui.SetForegroundWindow(handle)`
3. Fallback: `pygetwindow.getWindowsWithTitle(title)[0].activate()`
4. Skip auto-paste if target is Scribe itself (just clipboard)
5. 500ms delay after window activation before paste

### Swift adaptation notes

- Use `NSPasteboard` for clipboard operations on macOS
- `CGEvent` for simulating Cmd+V paste
- `NSRunningApplication.activate()` for window restoration
- Consider using Accessibility API (`AXUIElement`) for more reliable text insertion
- The "skip if target is self" check is important -- implement similarly

---

## 10. Key Patterns Worth Adapting to Swift

### Pattern 1: Hold-vs-Toggle Hotkey State Machine

```
idle -> [key down] -> hold_candidate
hold_candidate -> [key up, duration >= 0.25s] -> stop recording (hold mode)
hold_candidate -> [key up, duration < 0.25s] -> toggle mode (keep recording)
toggle -> [key down] -> stop recording
```

This is the most ergonomic hotkey behavior I've seen in a dictation app. Directly portable to Swift with `CGEvent` tap.

### Pattern 2: Analytics-First Design

Every transcription records:
- Word count, character count, audio duration, transcription time
- Application context (which app was the user in)
- Whether it was a command vs dictation
- Confidence score from Whisper

These feed into time-saved calculations. Users see their ROI immediately.

### Pattern 3: Separation of Raw vs Formatted Text

The database stores both `raw_text` and `text` (formatted), plus `ai_formatted` boolean. This enables:
- Showing users what was changed
- Learning from corrections (comparing raw -> formatted -> user_final)
- Rolling back AI formatting

### Pattern 4: Plugin CommandDefinition with Template Patterns

The `{placeholder}` pattern syntax is simple, powerful, and regex-based. Much better than full NLP for deterministic command matching. The test suite (`tests/test_pattern_matching.py`) is comprehensive.

### Pattern 5: Value Calculator as Motivation Engine

The "time saved vs typing" metric is a powerful retention tool. Simple formula:
```
time_saved = (word_count / 40_wpm * 60) - audio_duration_seconds
```

---

## 11. Gaps and Opportunities for PersonalScribe

### What Scribe has NOT built (but designed):
1. **Voice profile learning** - Only design docs exist
2. **Correction feedback loop** - No tracking of user edits to AI output
3. **Context-specific voice models** - No meeting vs email mode switching
4. **LLM-based text cleanup** - Only regex filler removal
5. **Multi-speaker detection** - Only single-user
6. **Cross-session context** - No "remember what I said yesterday"
7. **Milestone-based feature unlocking** - Only design docs
8. **Intent classification for commands** - Only strict pattern matching

### Where PersonalScribe can leap ahead:
1. **Apple Speech framework** for VAD instead of webrtcvad
2. **whisper.cpp / MLX Whisper** for native Metal-accelerated transcription
3. **On-device LLM** (e.g., MLX models) for text cleanup without API costs
4. **macOS Accessibility API** for reliable text insertion
5. **SwiftUI + Combine** for reactive UI instead of Qt signals
6. **CloudKit** for cross-device sync of voice profiles
7. **Shortcuts.app integration** for plugin-like extensibility
8. **NSUserActivity** for context capture instead of win32gui

### Architecture decisions to replicate:
- Plugin system with protocol-based registration
- Analytics from day 1
- Hold-vs-toggle hotkey state machine
- Separate raw/formatted text storage
- FTS5 for transcription search
- Config profiles with validation
- Background thread for transcription with main-thread UI updates

### Architecture decisions to improve upon:
- Add intent classification layer for commands (even simple keyword matching)
- Implement the voice profile learning system (Scribe only designed it)
- Use on-device ML instead of API for text cleanup
- Add undo/correction tracking from the start
- Build the feedback loop (raw -> AI -> user_final) into the core architecture
