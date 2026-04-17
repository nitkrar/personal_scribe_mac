# open-wispr Deep-Dive Exploration

Source: https://github.com/human37/open-wispr (MIT license, v0.34.0)
Cloned and analyzed: 2026-04-15

---

## 1. SPM Build Structure

**No Xcode project.** The entire app builds with `swift build` from the command line. The `.gitignore` excludes `.build/`, `.swiftpm/`, and `*.xcodeproj`.

### Package.swift (`/tmp/open-wispr/Package.swift`)

```swift
// swift-tools-version: 5.9
let package = Package(
    name: "open-wispr",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "OpenWisprLib",
            path: "Sources/OpenWisprLib",
            linkerSettings: [
                .linkedFramework("CoreAudio"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
            ]
        ),
        .executableTarget(
            name: "open-wispr",
            dependencies: ["OpenWisprLib"],
            path: "Sources/OpenWispr"
        ),
        .testTarget(
            name: "OpenWisprTests",
            dependencies: ["OpenWisprLib"],
            path: "Tests/OpenWisprTests"
        ),
    ]
)
```

Key observations:
- **Zero external dependencies.** No SPM package dependencies at all. whisper.cpp is a system-level dependency installed via Homebrew, not linked at build time.
- **Two-target structure:** `OpenWisprLib` (library) + `open-wispr` (executable). This cleanly separates testable logic from the entry point.
- **Framework linking is explicit** via `linkerSettings` -- CoreAudio, AVFoundation, AppKit are linked at the target level.
- **macOS 13+ minimum** (Ventura).
- **No resources in SPM** -- the AppIcon.icns lives in `Resources/` but is copied manually by `scripts/bundle-app.sh`, not via SPM resource bundling.

### File layout
```
Sources/
  OpenWispr/
    main.swift              # CLI entry point + NSApplication setup
  OpenWisprLib/
    AppDelegate.swift       # Orchestrator -- wires everything together
    StatusBarController.swift  # Menu bar icon, animations, menu
    AudioRecorder.swift     # AVAudioEngine capture
    Transcriber.swift       # Shells out to whisper-cli
    TextInserter.swift      # Clipboard + synthetic Cmd+V
    Config.swift            # JSON config loading/saving
    HotkeyManager.swift     # Global key event monitoring
    ModelDownloader.swift   # Downloads GGML models from HuggingFace
    KeyCodes.swift          # macOS virtual key code mappings
    Permissions.swift       # Accessibility + Microphone permission handling
    AudioDeviceManager.swift  # CoreAudio device enumeration
    TextPostProcessor.swift # "period" -> "." spoken punctuation
    RecordingStore.swift    # WAV file storage + pruning
    Version.swift           # Just `public static let version = "0.34.0"`
Tests/
  OpenWisprTests/
    TranscriberTests.swift
    TextInserterTests.swift
    ConfigTests.swift
    TextPostProcessorTests.swift
    RecordingStoreTests.swift
    KeyCodesTests.swift
```

**Recommendation for PersonalScribe:** Adopt this exact pattern. Two SPM targets (library + executable), zero external SPM deps, system whisper-cpp dependency. This keeps the build fast and avoids Xcode project file merge conflicts. The lib/exe split is essential for testability.

---

## 2. Menu Bar Icon State Machine

### States (defined in `StatusBarController.swift`)

```swift
enum State {
    case idle
    case recording
    case transcribing
    case downloading
    case waitingForPermission
    case copiedToClipboard
    case error(String)
}
```

### State transitions

```
                         +-- app launch --->  [waitingForPermission]
                         |                         |
                         |                    (AX granted)
                         |                         |
                         v                         v
[downloading] ------> [idle] <----------------+----+
                       |   ^                  |
                  (key down) (text inserted   |
                       |      or error+5s)    |
                       v                      |
                  [recording]                 |
                       |                      |
                  (key up)                    |
                       |                      |
                       v                      |
                  [transcribing] -------------+
                       |
                  (reprocess)
                       |
                       v
                  [copiedToClipboard] ---(1.5s)---> [idle]
```

### Icon rendering -- all programmatic, no image assets

Each state has a custom-drawn NSImage (18x18, template mode for dark/light adaptation):

| State | Visual | Implementation |
|-------|--------|----------------|
| `idle` | 5 rounded bars (audio waveform icon) | `drawLogo(active:)` -- static bars with heights [4, 8, 12, 8, 4] |
| `recording` | Animated wave bars | 30 pre-rendered frames, bars pulse via sine wave with phase offsets. Timer at 30fps. |
| `transcribing` | 3 bouncing dots | 30 pre-rendered frames, dots bounce with sine wave. Timer at 30fps. |
| `downloading` | Progress ring + arrow | Circle with progress arc (clockwise from top), pulsing when no progress. |
| `waitingForPermission` | Lock icon | Drawn with bezier paths (rectangle body + arc shackle). |
| `copiedToClipboard` | Checkmark | Simple two-segment check path. |
| `error` | Warning triangle | Triangle outline + exclamation mark. |

The `state` property has a `didSet` that calls `updateIcon()`, which stops any running animation timer and starts the appropriate new one.

**Pattern worth adopting:** Pre-rendering animation frames is smart -- avoids per-frame drawing overhead. All icons are drawn programmatically as `NSImage(size:flipped:)` with `NSBezierPath`, marked `isTemplate = true` so macOS automatically handles light/dark mode. No icon assets needed.

**Pattern to improve:** The 30fps timer for animations is aggressive for a menu bar icon. Consider 15fps or even 10fps -- the user won't notice the difference and it saves CPU.

---

## 3. Audio Capture

### File: `Sources/OpenWisprLib/AudioRecorder.swift`

```swift
class AudioRecorder {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    var preferredDeviceID: AudioDeviceID?
```

### Setup flow

1. Creates a fresh `AVAudioEngine()` on every recording start (not reused).
2. If a preferred device ID is set, calls `setInputDevice()` which uses `AudioUnitSetProperty` with `kAudioOutputUnitProperty_CurrentDevice` on the engine's input node's audio unit.
3. Gets the input node's native format (whatever the hardware provides).
4. Creates an `AVAudioConverter` to resample to **16kHz mono Float32** (whisper.cpp requirement).
5. Opens a WAV file for writing with settings: 16kHz, 1 channel, 16-bit integer PCM.
6. Installs a tap on bus 0 with buffer size 4096 in the hardware's native format.
7. In the tap callback, converts each buffer to 16kHz mono and writes to the file.

### Key technical details

**Sample rate handling:**
```swift
let recordingFormat = AVAudioFormat(
    commonFormat: .pcmFormatFloat32,
    sampleRate: 16000,
    channels: 1,
    interleaved: false
)!

// Converter handles resampling from hardware rate to 16kHz
let converter = AVAudioConverter(from: format, to: recordingFormat)
```

The converted buffer capacity is calculated proportionally:
```swift
let convertedBuffer = AVAudioPCMBuffer(
    pcmFormat: recordingFormat,
    frameCapacity: AVAudioFrameCount(
        Double(buffer.frameLength) * 16000.0 / format.sampleRate
    )
)!
```

**File format:** WAV files with 16-bit integer PCM at 16kHz mono -- this is exactly what whisper.cpp expects.

**Temp file management:** Two modes based on `maxRecordings` config:
- If `maxRecordings == 0` (privacy mode): uses `RecordingStore.tempRecordingURL()` which writes to `/tmp/open-wispr-recording.wav`, deleted after transcription via `defer`.
- If `maxRecordings > 0`: uses `RecordingStore.newRecordingURL()` which creates timestamped files in `~/.config/open-wispr/recordings/recording-2026-04-15-143022-A1B2C3D4.wav`. Old recordings pruned after each transcription.

**Stop flow:**
```swift
func stopRecording() -> URL? {
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil
    audioFile = nil
    isRecording = false
    return currentOutputURL
}
```

**Recommendation for PersonalScribe:**
- Adopt the AVAudioConverter approach -- it handles any input sample rate gracefully.
- The "new engine per recording" pattern is simple and avoids stale state, but adds ~50ms latency on start. For a hold-to-talk app this is fine. Consider pre-warming the engine if latency matters.
- The privacy mode (temp file + delete) is a thoughtful feature to adopt.
- Add error handling for the converter -- the current code silently drops frames if conversion fails.

### Audio Device Selection (`AudioDeviceManager.swift`)

Enumerates CoreAudio devices, filters for input devices, excludes virtual/aggregate devices:
```swift
static func listInputDevices() -> [AudioInputDevice]
```
Uses `kAudioDevicePropertyTransportType` to filter out `kAudioDeviceTransportTypeAggregate` and `kAudioDeviceTransportTypeVirtual`. This is a good practice to avoid confusing users with system-internal devices.

---

## 4. Text Injection

### File: `Sources/OpenWisprLib/TextInserter.swift`

The approach is: **save clipboard -> put text on clipboard -> simulate Cmd+V -> restore clipboard**.

```swift
func insert(text: String) {
    let pasteboard = NSPasteboard.general
    let savedItems = savePasteboard(pasteboard)     // Deep copy all items/types
    pasteboard.clearContents()
    pasteboard.setString(text, forType: .string)
    simulatePaste()                                  // Synthetic Cmd+V via CGEvent
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        self.restorePasteboard(pasteboard, items: savedItems)
    }
}
```

### Clipboard save/restore

Full fidelity -- saves ALL pasteboard items with ALL their types and data:
```swift
private func savePasteboard(_ pasteboard: NSPasteboard) -> [[(NSPasteboard.PasteboardType, Data)]] {
    guard let items = pasteboard.pasteboardItems else { return [] }
    return items.map { item in
        item.types.compactMap { type in
            guard let data = item.data(forType: type) else { return nil }
            return (type, data)
        }
    }
}
```

### Keyboard layout-aware paste simulation

The "V" key is not always keycode 9. On non-QWERTY layouts (Dvorak, AZERTY, etc.), the keycode for Cmd+V varies. The code resolves it at init time:

```swift
init() {
    self.pasteKeyCode = TextInserter.resolveKeyCode(for: "v") ?? 9
}
```

`resolveKeyCode` uses the Carbon `UCKeyTranslate` API to scan all 128 keycodes against the current keyboard layout and find which one produces "v":

```swift
private static func resolveKeyCode(for target: Character) -> CGKeyCode? {
    guard let inputSource = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
        let rawLayoutData = TISGetInputSourceProperty(inputSource, kTISPropertyUnicodeKeyLayoutData)
    // ... scans keyCode 0..<128 via UCKeyTranslate
}
```

### CGEvent paste simulation

```swift
private func simulatePaste() {
    guard let source = CGEventSource(stateID: .hidSystemState),
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
    keyDown.flags = .maskCommand
    keyUp.flags = .maskCommand
    keyDown.post(tap: .cghidEventTap)
    keyUp.post(tap: .cghidEventTap)
}
```

**How it handles different apps:** It doesn't -- it relies on the universal Cmd+V shortcut. This works for essentially all macOS text inputs. No per-app logic. No Accessibility API text insertion (which would be more correct but much harder to get right across apps).

**Recommendation for PersonalScribe:**
- Adopt this clipboard-swap approach. It's the same pattern used by commercial dictation apps.
- The 0.1s delay before restoring the clipboard is a race condition risk. Some apps process paste asynchronously. Consider increasing to 0.15-0.2s or detecting paste completion.
- The keyboard layout resolution via UCKeyTranslate is excellent -- adopt this for international keyboard support.
- Consider adding an alternative path using `AXUIElementSetAttributeValue` with `kAXValueAttribute` for apps that support Accessibility, falling back to clipboard paste.
- **Known limitation:** If the user copies something to clipboard during the 0.1s window, the restore will overwrite it.

---

## 5. whisper.cpp Integration

### File: `Sources/OpenWisprLib/Transcriber.swift`

**whisper.cpp is NOT linked as a library.** It's called as an external process via `Process()` (equivalent to `NSTask`):

```swift
public func transcribe(audioURL: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: whisperPath)
    process.arguments = [
        "-m", modelPath,
        "-f", audioURL.path,
        "-l", language,
        "--no-timestamps",
        "-nt",    // no token timestamps
    ]
    // Optional: suppress punctuation tokens for spoken-punctuation mode
    if spokenPunctuation {
        args += ["--suppress-regex", "[,\\.\\?!;:\\-\u{2014}]"]
    }
```

### Binary discovery

Searches multiple locations:
```swift
static func findWhisperBinary() -> String? {
    let candidates = [
        "/opt/homebrew/bin/whisper-cli",    // Apple Silicon Homebrew
        "/usr/local/bin/whisper-cli",        // Intel Homebrew
        "/opt/homebrew/bin/whisper-cpp",     // Older name
        "/usr/local/bin/whisper-cpp",        // Older name
    ]
    // Falls back to `which whisper-cli` and `which whisper-cpp`
```

### Model discovery

```swift
static func findModel(modelSize: String) -> String? {
    let modelFileName = "ggml-\(modelSize).bin"
    let candidates = [
        "\(Config.configDir.path)/models/\(modelFileName)",           // ~/.config/open-wispr/models/
        "/opt/homebrew/share/whisper-cpp/models/\(modelFileName)",     // Homebrew models
        "/usr/local/share/whisper-cpp/models/\(modelFileName)",        // Intel Homebrew
        "\(home)/.cache/whisper/\(modelFileName)",                      // Common cache location
    ]
```

### Metal acceleration

**There is no explicit Metal setup in open-wispr.** Metal acceleration is handled entirely by the whisper-cpp binary itself. When whisper-cpp is compiled with Metal support (which the Homebrew formula does by default on Apple Silicon), it automatically uses the GPU. The install script enforces Apple Silicon:

```bash
if [[ "$(uname -m)" != "arm64" ]]; then
    die "Apple Silicon (M1 or later) is required."
fi
```

### Output processing

whisper.cpp output is cleaned:
1. Strip whisper marker tokens like `[BLANK_AUDIO]`, `[Music]`, `(silence)`, etc.
2. Collapse multiple whitespace to single space
3. Trim leading/trailing whitespace

The marker stripping is regex-based with a whitelist of known markers:
```swift
private static let knownMarkers: Set<String> = [
    "BLANK_AUDIO", "blank_audio", "Music", "MUSIC", "Applause", ...
]
```

### Spoken punctuation post-processing (`TextPostProcessor.swift`)

When `spokenPunctuation` is enabled, whisper.cpp is told to suppress actual punctuation tokens, and then spoken words are converted:
- "period" / "full stop" -> "."
- "comma" -> ","
- "question mark" -> "?"
- "new line" / "newline" -> "\n"
- "new paragraph" -> "\n\n"
- etc.

Followed by spacing fixes (remove space before punctuation, ensure space after punctuation).

**Recommendation for PersonalScribe:**
- The subprocess approach is pragmatic but adds ~100-200ms overhead per transcription for process creation. For faster response, consider linking whisper.cpp as a C library directly (using SPM's C interop or a bridging header). However, the subprocess approach is much simpler to maintain and debug.
- Adopt the marker stripping logic -- these false positives from whisper are common.
- The spoken punctuation feature is valuable. Adopt the suppression regex + post-processing approach.
- Consider adding a `--threads` flag to control CPU usage during transcription.

---

## 6. Config System

### File: `Sources/OpenWisprLib/Config.swift`

**Location:** `~/.config/open-wispr/config.json`

### JSON structure

```json
{
    "hotkey": {
        "keyCode": 63,
        "modifiers": []
    },
    "modelSize": "base.en",
    "language": "en",
    "spokenPunctuation": false,
    "maxRecordings": 0,
    "toggleMode": false,
    "audioInputDeviceID": null
}
```

### Config struct (Codable)

```swift
public struct Config: Codable {
    public var hotkey: HotkeyConfig
    public var modelPath: String?           // Unused legacy field
    public var modelSize: String
    public var language: String
    public var spokenPunctuation: FlexBool?
    public var maxRecordings: Int?
    public var toggleMode: FlexBool?
    public var audioInputDeviceID: UInt32?
}
```

### FlexBool -- tolerant boolean parsing

Smart wrapper that accepts bool, string, or int:
```swift
public struct FlexBool: Codable {
    public let value: Bool
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let b = try? container.decode(Bool.self) { value = b }
        else if let s = try? container.decode(String.self) {
            value = ["true", "yes", "1"].contains(s.lowercased())
        } else if let i = try? container.decode(Int.self) { value = i != 0 }
        else { value = false }
    }
}
```

This means users can write `"toggleMode": true`, `"toggleMode": "yes"`, or `"toggleMode": 1` in their config and it all works.

### Loading behavior

```swift
public static func load() -> Config {
    guard let data = try? Data(contentsOf: configFile) else {
        let config = Config.defaultConfig
        try? config.save()    // Creates default config if none exists
        return config
    }
    do {
        return try JSONDecoder().decode(Config.self, from: data)
    } catch {
        fputs("Warning: unable to parse ...\n", stderr)
        return Config.defaultConfig    // Falls back to defaults on parse error
    }
}
```

### Live reload

The menu bar has a "Reload Configuration" option that calls `AppDelegate.reloadConfig()`. The `applyConfigChange()` method:
1. Re-creates the `Transcriber` with new model/language
2. Re-creates the `TextInserter`
3. Stops and re-starts the `HotkeyManager` with new key binding
4. If the new model isn't downloaded, triggers background download
5. Rebuilds the menu

**Recommendation for PersonalScribe:**
- Adopt the `~/.config/` convention and JSON format.
- The FlexBool pattern is user-friendly -- adopt it.
- Consider adding file watching (via `DispatchSource.makeFileSystemObjectSource`) for automatic config reload instead of manual menu click.
- The graceful fallback to defaults on parse error is good -- don't crash on bad config.

---

## 7. Toggle vs Hold-to-Talk

### Implementation in `AppDelegate.swift`

Both modes use the same `HotkeyManager` (key down / key up callbacks). The difference is purely in how `handleKeyDown` and `handleKeyUp` respond:

```swift
private func handleKeyDown() {
    let isToggle = config.toggleMode?.value ?? false
    if isToggle {
        if isPressed {
            handleRecordingStop()    // Second press = stop
        } else {
            handleRecordingStart()   // First press = start
        }
    } else {
        guard !isPressed else { return }  // Ignore key repeat
        handleRecordingStart()
    }
}

private func handleKeyUp() {
    let isToggle = config.toggleMode?.value ?? false
    if isToggle { return }    // Ignore key-up in toggle mode
    handleRecordingStop()
}
```

The `isPressed` boolean tracks current recording state. In hold mode, key-down starts and key-up stops. In toggle mode, first key-down starts, second key-down stops, and key-up is ignored.

**Recommendation for PersonalScribe:** This is clean and simple. Adopt as-is. The `guard !isPressed` in hold mode prevents key-repeat from re-triggering -- important detail.

---

## 8. Homebrew Distribution

### Formula (`Formula/open-wispr.rb`)

```ruby
class OpenWispr < Formula
  desc "Push-to-talk voice dictation for macOS using Whisper"
  homepage "https://github.com/human37/open-wispr"
  url "https://github.com/human37/open-wispr.git", tag: "v0.9.1"
  license "MIT"

  depends_on "whisper-cpp"
  depends_on :macos

  def install
    system "swift", "build", "-c", "release", "--disable-sandbox"
    system "bash", "scripts/bundle-app.sh", ".build/release/open-wispr", "OpenWispr.app", version.to_s
    bin.install ".build/release/open-wispr"
    prefix.install "OpenWispr.app"
  end

  def post_install
    target = Pathname.new("#{Dir.home}/Applications/OpenWispr.app")
    target.dirname.mkpath
    rm_rf target if target.exist? && !target.symlink?
    ln_sf prefix/"OpenWispr.app", target
  end

  service do
    run [opt_prefix/"OpenWispr.app/Contents/MacOS/open-wispr", "start"]
    keep_alive successful_exit: false
    log_path var/"log/open-wispr.log"
    error_log_path var/"log/open-wispr.log"
    process_type :interactive
  end
end
```

### Key design decisions

1. **Build from source in formula** -- `swift build -c release --disable-sandbox`. This means every install compiles from source (slow but universal).
2. **App bundle creation** -- `scripts/bundle-app.sh` creates an `.app` wrapper with Info.plist. Critical for macOS permission system which identifies apps by bundle ID.
3. **Symlink to ~/Applications** -- The post_install creates a symlink so macOS recognizes it for Accessibility/Microphone permissions via LaunchServices.
4. **brew services integration** -- The `service` block defines a launchd plist. `brew services start open-wispr` creates a LaunchAgent that auto-starts on login.
5. **`process_type :interactive`** -- Important for macOS to allow the background service to interact with Accessibility APIs.

### App bundle (`scripts/bundle-app.sh`)

Creates a minimal `.app` structure:
```
OpenWispr.app/
  Contents/
    MacOS/
      open-wispr          # The binary
    Resources/
      AppIcon.icns
    Info.plist
```

Critical Info.plist entries:
- `CFBundleIdentifier`: `com.human37.open-wispr` (used for permission grants)
- `LSUIElement`: `true` (no Dock icon -- menu bar only)
- `NSMicrophoneUsageDescription`: Required for microphone access

The bundle is ad-hoc code signed: `codesign --force --sign - --identifier com.human37.open-wispr "$APP_DIR"`

### Install script (`scripts/install.sh`)

Orchestrated guided install:
1. Check Apple Silicon (required for Metal)
2. Clean up any previous installation
3. `brew tap human37/open-wispr` then `brew install open-wispr`
4. Start service, wait for microphone permission
5. Wait for Accessibility permission (opens System Settings, polls log file)
6. Wait for model download
7. Verify service is running

The script monitors `/opt/homebrew/var/log/open-wispr.log` by polling with `grep` for status messages like "Microphone: granted", "Accessibility: granted", "Ready."

### Uninstall script (`scripts/uninstall.sh`)

Clean removal:
1. Stop service + pkill
2. `brew uninstall` + `brew untap`
3. Remove ~/Applications/OpenWispr.app
4. Remove ~/.config/open-wispr (config + models)
5. Remove logs
6. Unregister from LaunchServices via `lsregister -u`

**Recommendation for PersonalScribe:**
- The app bundle wrapper is essential -- macOS permission system needs a bundle ID.
- The symlink to ~/Applications is clever -- avoids copying but still registers with LaunchServices.
- Consider using `brew install --build-bottle` for pre-built bottles to avoid compile times for users.
- The log-polling install script is fragile but functional. Consider a more robust IPC mechanism (write a status file, or use a Unix socket).
- The `process_type :interactive` in the service block is critical for Accessibility to work from a launchd service.

---

## 9. Model Management

### File: `Sources/OpenWisprLib/ModelDownloader.swift`

**Source:** HuggingFace (`https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-{size}.bin`)

**Storage:** `~/.config/open-wispr/models/ggml-{size}.bin`

### Supported models

```swift
public static let supportedModels: [String] = [
    "tiny.en", "tiny",
    "base.en", "base",
    "small.en", "small",
    "medium.en", "medium",
    "large-v3-turbo", "large",
]
```

The `.en` variants are English-only (smaller, faster). The multilingual variants support 90+ languages.

### Download implementation

Uses `URLSession` with delegate for progress tracking:

```swift
public static func download(modelSize: String, onProgress: ((Double) -> Void)? = nil) throws {
    // Creates URLSession with delegate
    // Synchronous via DispatchSemaphore
    // Progress callback reports 0-100%
}
```

The download is **synchronous** (blocks via semaphore) but is always called from a background thread. Progress is reported to the main thread for UI updates.

### Model validation

After download, validates the file has a known GGML/GGJT/GGUF magic number:
```swift
public static func isValidGGMLFile(at url: URL) -> Bool {
    // Reads first 4 bytes
    // Checks against: 0x67676d6c (ggml), 0x67676a74 (ggjt), 0x46554747 (GGUF)
    let knownMagics: Set<UInt32> = [0x67676d6c, 0x67676a74, 0x46554747]
    return knownMagics.contains(magicU32)
}
```

This catches the common case where a corporate proxy returns an HTML error page instead of the model file.

### Model search order

When looking for an existing model:
1. `~/.config/open-wispr/models/` (app's own download location)
2. `/opt/homebrew/share/whisper-cpp/models/` (Homebrew whisper-cpp models)
3. `/usr/local/share/whisper-cpp/models/` (Intel Homebrew)
4. `~/.cache/whisper/` (common cache location)

### Auto-download on startup

If the configured model isn't found locally, `AppDelegate.setupInner()` triggers a download before the app becomes ready. The status bar shows download progress.

If a model is switched via the menu and the new model isn't downloaded, it downloads in the background while the app remains usable.

**Recommendation for PersonalScribe:**
- Adopt the multi-location model search -- users who already have whisper-cpp models shouldn't re-download.
- The GGML magic validation is important -- adopt it.
- Consider supporting GGUF format models (newer format) which have better metadata.
- The synchronous-with-semaphore download pattern works but is inelegant. Consider async/await if targeting macOS 13+.
- Add download resumption (HTTP Range headers) for large models that fail mid-download.

---

## 10. Additional Patterns Worth Noting

### Permissions handling (`Permissions.swift`)

- **Microphone:** Uses `AVCaptureDevice.requestAccess(for: .audio)` with synchronous semaphore wait.
- **Accessibility:** Checks `AXIsProcessTrusted()`, opens System Settings via URL scheme `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`.
- **Upgrade detection:** Tracks last-seen version in `~/.config/open-wispr/.last-version`. On version change, resets Accessibility permissions via `tccutil reset Accessibility com.human37.open-wispr` because macOS sometimes invalidates permissions after binary changes.

### NSApplication setup (`main.swift`)

The app runs as a "headless" NSApplication:
```swift
let app = NSApplication.shared
app.setActivationPolicy(.accessory)    // No Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
```

Combined with `LSUIElement: true` in Info.plist, this creates a pure menu-bar app.

Also notable: line-buffered stdout/stderr for log tailing:
```swift
setvbuf(stdout, nil, _IOLBF, 0)
setvbuf(stderr, nil, _IOLBF, 0)
```

### CI (`/.github/workflows/ci.yml`)

Four parallel jobs:
1. **build** -- `swift build -c release` (only if Swift files changed)
2. **unit-tests** -- `swift test` (only if Swift files changed)
3. **install-test** -- shellcheck on scripts + install smoke test
4. **transcription-test** -- Full integration test: generates audio via `say` command, transcribes with whisper-cpp, validates output

The transcription test (`scripts/test-transcription.sh`) is clever: uses macOS `say` to generate test audio, converts to 16kHz WAV with `afconvert`, then runs whisper-cpp and checks for expected words.

### HotkeyManager details

Uses `NSEvent.addGlobalMonitorForEvents` (not `CGEvent` taps) for key detection. Handles both regular keys and modifier-only keys (like fn/globe). Modifier-only keys use `.flagsChanged` events with a toggle flag.

Modifier key codes recognized as modifier-only:
```swift
[54, 55, 56, 58, 59, 60, 61, 62, 63]
// rightcmd, cmd, shift, option, ctrl, rightshift, rightoption, rightctrl, fn
```

---

## Summary: Adopt vs Avoid

### Adopt

1. **SPM-only build with lib/exe split** -- no Xcode project, clean testability
2. **Zero external SPM dependencies** -- whisper-cpp as system dependency
3. **Programmatic menu bar icons** with template images -- automatic dark/light mode
4. **Pre-rendered animation frames** -- efficient menu bar animations
5. **AVAudioConverter for sample rate conversion** -- handles any hardware sample rate
6. **Clipboard save/restore with CGEvent paste** -- universal text injection
7. **UCKeyTranslate for keyboard layout detection** -- international keyboard support
8. **FlexBool for config parsing** -- user-friendly config files
9. **GGML magic validation** after model download
10. **Multi-location model search** -- reuse existing whisper-cpp models
11. **Privacy mode** (temp file + immediate delete)
12. **Spoken punctuation** with suppression regex + post-processing
13. **Upgrade detection** with version tracking for permission reset
14. **App bundle wrapper** for macOS permission system
15. **`LSUIElement: true`** for menu-bar-only app
16. **`setvbuf` line buffering** for log tailing

### Avoid / Improve

1. **30fps animation timers** -- excessive for menu bar, use 10-15fps
2. **0.1s clipboard restore delay** -- too short, race condition risk
3. **Synchronous semaphore waits** for downloads/permissions -- use async/await
4. **Log-file polling in install script** -- fragile, consider status file IPC
5. **No download resumption** -- large model downloads can fail mid-stream
6. **Process-based whisper-cpp invocation** -- adds overhead per transcription; consider direct C library linking for lower latency
7. **No file watching for config** -- requires manual reload
8. **Version in source code** (`Version.swift`) -- should be injected at build time
9. **No error state timeout customization** -- hardcoded 5s
10. **Global monitor only** -- `addGlobalMonitorForEvents` doesn't capture events when the app itself is focused (though irrelevant for a menu-bar-only app)
