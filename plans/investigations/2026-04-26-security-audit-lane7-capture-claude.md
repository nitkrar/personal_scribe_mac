# Security Audit — Lane 7: Capture pipeline + secrets (Claude reviewer)

Date: 2026-04-26
Reviewer: Claude (independent of Codex Lane 7).
Scope: READ-ONLY audit of audio buffer lifetime + secrets/env exposure.

## 1. Threat-model framing

Two attacker outcomes drive this lane:

**(a) Audio buffer leak.** Captured microphone audio is the highest-sensitivity payload in the app — verbatim recordings of the user. Risk scales with three factors:
1. **Number of components touching the buffer** — each hop is an opportunity for a copy that escapes the in-memory pipeline.
2. **Persistence to disk.** Any temp file, debug dump, or "just in case" cache turns a transient buffer into an artifact discoverable post-hoc by malware, backup software, or a forensic adversary.
3. **Cross-process / network egress.** Send-to-cloud, IPC, telemetry — all out of scope for an offline-first app, but worth confirming.

The contract this lane verifies: PCM samples flow capture → resampler → in-memory `PCMBuffer` (`[Float]`) → VAD chunk + transcription engine, and never land on disk in any form.

**(b) Hardcoded secrets / env-var supply chain.** A bundled API key, OAuth token, or shared HMAC secret would (i) ship to every user's machine, (ii) be discoverable by `strings` on the binary, (iii) typically have far more privilege than any single user should have. An `ENV`-driven runtime path is a softer variant — it lets an attacker who controls the launch environment redirect the app's behavior. Both classes are preventable through audit.

## 2. Files audited

Audio path (full read):
- `Sources/PersonalScribeAudio/AVAudioCaptureService.swift` (345 lines)
- `Sources/PersonalScribeAudio/AudioEngineDriver.swift` (263 lines)
- `Sources/PersonalScribeAudio/AudioResampler.swift` (135 lines)
- `Sources/PersonalScribeAudio/SystemAudioMuter.swift` (64 lines)
- `Sources/PersonalScribeAudio/AVFoundationInputDeviceProvider.swift` (read first 80 lines)
- `Sources/PersonalScribeAudio/AudioLevelCalculator.swift` (referenced)
- `Sources/PersonalScribeCore/PCMBuffer.swift` (32 lines, full)
- `Sources/PersonalScribeCore/Audio/AudioInputDevice.swift`
- `Sources/PersonalScribeVAD/FluidAudioVadProvider.swift` (105 lines)
- `Sources/PersonalScribeVAD/FluidAudioVadSession.swift` (62 lines)
- `Sources/PersonalScribeVAD/VadMonitoring.swift` (37 lines)
- `Sources/PersonalScribeTranscription/FluidAudioTranscriber.swift` (245 lines)
- `Sources/PersonalScribeTranscription/FluidAudioInferenceClient.swift` (68 lines)
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioStreamingTranscriberAdapter.swift` (315 lines)
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift` (head)
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioOfflineDiarizerAdapter.swift` (head)
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioQwenTranscriberAdapter.swift` (head)
- `Sources/PersonalScribeSession/Pipeline/Orchestrator/SessionPipelineOrchestrator.swift` (`bufferedAudio` lifecycle)
- `Sources/PersonalScribeSession/Pipeline/Processors/PCMBufferSlicing.swift`
- `Sources/PersonalScribeSession/Pipeline/Processors/DiarizedTurnTranscriptionProcessor.swift` (head)

Secrets / env / preferences (sweep across all 224 `Sources/**/*.swift`):
- Greps run: `ProcessInfo.processInfo.environment`, `getenv`, `KeychainAccess`, `Bearer `, `api_key|api-key|apikey|secret|password|x-api`, `"http"`/`URL(string:`, high-entropy literals (`"[A-Za-z0-9_/+=\-]{40,}"`), `defaults.set(`, `setObject`, `dump|debugWrite|saveAudio|exportAudio`, `URLSession|URLRequest|HTTPRequest`, `FileHandle|OutputStream|Pipe`.
- Targeted reads: `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift` (full), `AppConfig.swift` (full), `Storage/AppStorageLocator.swift` (head), `BaseDirectoryMigrator.swift` (head), `Database/AppDatabase.swift` (full), `TranscriptStore.swift` (full), `Models/Selection/ModelDescriptor.swift` (URL builder).

## 3. Findings

### Audio buffer lifetime — clean

The traced flow is:

1. **Allocation.** `AVAudioCaptureService.installTap` (`AVAudioCaptureService.swift:107-114`) receives an `AVAudioPCMBuffer` on AVFoundation's tap thread, calls the static `extractMonoSamples` (lines 294-320) which copies the float channel data into a `[Float]` and discards the AVAudioPCMBuffer immediately. The `[Float]` is the only thing that crosses the actor boundary.
2. **Resample.** `AudioResampler.performResample` (`AudioResampler.swift:40-130`) builds short-lived `AVAudioPCMBuffer`s (lines 74, 91) only as scratch buffers for `AVAudioConverter`; output is copied back to a `[Float]` via `Array(UnsafeBufferPointer(...))` (line 122) and the AVAudioPCMBuffers go out of scope. Result is wrapped in `PCMBuffer` (`PCMBuffer.swift`), which is `Sendable` + `Equatable` and contains `samples: [Float]` only — no file URL, no persistence hooks.
3. **Pipeline fan-out.** `SessionPipelineOrchestrator.consumeCaptureStream` (line 618) appends each `PCMBuffer` to an in-memory `bufferedAudio: [PCMBuffer]` (line 633) for replay-mode transcription. Cleared via `removeAll(keepingCapacity:)` at five sites (lines 280, 341, 365, 425, 430) — every stop/cancel/error path. VAD branch (line 644) feeds `buffer.samples` into the per-session `FluidAudioVadSession` actor, which itself accumulates a `[Float]` chunk and discards.
4. **Transcription consumption.** `FluidAudioTranscriber.transcribe` (line 132) hands `audio.samples` directly to `inference.transcribe(samples:)`. `PrivateFluidAudioInferenceClient.transcribe` (line 51-57) calls `AsrManager.transcribe(samples, source: .microphone)` and returns text + duration. No retention. Streaming adapter (`FluidAudioStreamingTranscriberAdapter.swift:228-258`) constructs an `AVAudioPCMBuffer` from the `[Float]` samples per call — scratch buffer, scoped to the `process(audioBuffer:)` await, then released.
5. **No disk writes.** Repo-wide search for `AVAudioFile`, `audioFile.write`, and `.write(to:` returns zero hits in the audio path. The two `.write(to:)` matches (`ModelBoundProcessorProvider.swift:232`, `WorkflowModeStore.swift:72`) are unrelated — model artifact stubs and JSON workflow-mode persistence respectively. No `.wav` / `.m4a` / `.aiff` / `.caf` mentions anywhere. No `FileHandle`, `OutputStream`, or `Pipe` usage in the project.
6. **No log-side leak.** Greps for `os_log .* samples` and similar return only metadata (sample rates as numbers, frame counts) — never the buffer contents.

**Verdict: Audio stays in-memory from `AVAudioEngine` tap to FluidAudio `AsrManager` consumption.** No findings.

### Env vars — single, narrow, deliberate

**Finding S1 (informational, not a defect):** `PERSONAL_SCRIBE_BASE_DIR` env var is read in `Sources/PersonalScribeCore/Storage/AppConfig.swift:101`. It overrides the default Application Support directory. Used by tests/dev (per the resolution-order doc-comment lines 46-50). Accepted dev-loop affordance; it does not control any code path that exfiltrates data or alters trust decisions, only redirects where files are written/read on the user's own disk. **No mitigation needed.** Documented in code.

No other `ProcessInfo.processInfo.environment` reads were found beyond the four sites that all forward to this same one variable lookup (`AppConfig`, `AppStorageLocator`, `BaseDirectoryMigrator`, and `AppConfig.baseDirectory`).

No `getenv` calls anywhere in `Sources/`.

### Hardcoded secrets — none

Greps for `KeychainAccess`, `Bearer `, `api_key`, `apikey`, `secret`, `password`, `x-api`, `credential`, `auth.*header`, and high-entropy 40+ char alphanumeric literals all return zero matches across `Sources/**/*.swift`. The only "token"/"secret"-named symbols are unrelated:
- UUID-based grace-window tokens in `SessionPipelineOrchestrator.swift` (lines 689, 710, 729+).
- ASR token timings (`tokenTimings`) — speech-recognition token boundaries, not auth.
- High-entropy hits in `silero-vad.mlmodelc/model.mil` are CoreML tensor identifiers (e.g. `lstm_out_1_batch_first_lstm_h0_squeeze_axes_0`), not credentials.

**Verdict: No hardcoded secrets.**

### Hardcoded URLs — two; both expected

1. `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:195` — `https://huggingface.co/{repository}/resolve/{revision}/{relativePath}`. Per threat model, HuggingFace download URLs are explicitly allowed. Pinning to repository + revision is the right shape (no floating `latest`).
2. `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift:84` — `https://mythlok.com/ninimma/`. Marketing/about link rendered as `Link(destination:)` in SwiftUI; user-initiated, not auto-fetched.

The `URL(string: "x-apple.systempreferences:...")` in `GeneralTab.swift:136` is a system Settings deep-link, not a network endpoint. The `URL(string: "about:blank")` in `PillOverlayController.swift:465` is a placeholder.

No `URLSession`, `URLRequest`, or `HTTPRequest` constructions exist anywhere in `Sources/` — the app does not initiate HTTP itself; all network is delegated to the FluidAudio dependency for model downloads.

### UserDefaults — no sensitive content

Full inventory of UserDefaults keys (from `defaults.set` writes + `userDefaultsKey` declarations):

| Key | Type | Module | Sensitive? |
| --- | --- | --- | --- |
| `BaseDirectoryPath` | String (path) | `AppConfig` | No — file path on user's own disk |
| `SelectedAudioInputDeviceID` | String (`AVCaptureDevice.uniqueID`) | `AVFoundationInputDeviceProvider` | Low — stable hardware UID, but not PII |
| `RecordingHotkey` | encoded hotkey config | `HotkeyPreference` | No |
| `OnboardingCompleted` | Bool | `OnboardingState` | No |
| `BackgroundMode` | enum raw | `BackgroundLaunchPreference` | No |
| `VadAutoStopEnabled` / `VadShowStoppingWarning` / `VadShowAutoStoppedNotification` / `VadSilenceDurationSeconds` | Bool/Bool/Bool/TimeInterval | `VadPreferencePersistence` | No |
| `MuteOutputWhileRecording` | Bool | `MuteOutputWhileRecordingPreference` | No |
| `AutoPasteEnabled` / `ClipboardRestoreEnabled` / `PasteRestoreDelaySeconds` | Bool/Bool/Double | various Settings | No |
| `PillAppearance` / `PillStyle` / `PillVisibilityMode` / `WindowTint` / `AppTheme` / `WaveformDecayMode` | enum raw | Theme + Overlay | No |
| `PreferenceMigrationVersion` and legacy migration flags | Int / Bool | `PreferenceMigrator`, `LegacyToggleMigrator` | No |

**No transcript text, recording paths, audio buffers, or PII in UserDefaults.** The `SelectedAudioInputDeviceID` is the only identifier that could fingerprint hardware, but device UIDs are already exposed to any app via `AVCaptureDevice.uniqueID` and are device-scoped, not user-scoped. Acceptable.

### Transcript-text persistence — by design, with reasonable guards

`Sources/PersonalScribeCore/Database/AppDatabase.swift` opens an unencrypted SQLite database under `<recordings>/transcripts.sqlite` storing every transcription's plaintext (`TranscriptStore.swift:7`). This is the documented Phase 3 behavior ("notes = transcripts" — every transcription stored unconditionally; see `~/.claude/projects/.../memory/project_phase3_notes_equals_history.md`).

Mitigations already in place:
- `AppDatabase.setPermissionsIfPresent` (lines 192-204) sets `0o600` on the SQLite file at every open.
- File lives under `~/Library/Application Support/personal_scribe/recordings/`, which inherits the user's HOME ACL.
- macOS FileVault (when enabled) provides at-rest encryption.

**Not a finding** — this is product intent, scoped per the threat model. It's worth flagging that an SQLite-cipher upgrade or per-row encryption is in scope only if the threat model later includes "attacker has read access to the user's home directory while FileVault is unlocked," which is not the current model.

## 4. Coverage gaps

- **FluidAudio dependency internals** were NOT audited. `AsrManager.transcribe`, `VadManager.processStreamingChunk`, `StreamingEouAsrManager.process`, and `AsrModels.load` are all third-party Swift Package code (`fluid-audio` repo). They could in principle write debug audio dumps or maintain caches that this audit cannot see. The relevant cross-trust hop:
  - `FluidAudioInferenceClient.transcribe` (line 52) → `AsrManager.transcribe(samples, source: .microphone)`.
  - `FluidAudioStreamingTranscriberAdapter.executeTranscription` (line 152) → `manager.process(audioBuffer:)`.
  - `FluidAudioVadSession.ingest` (line 46) → `inference(chunk, streamState, config)` → `VadManager.processStreamingChunk`.
  Recommend a follow-up audit of the FluidAudio source if the threat model demands end-to-end coverage. (`fluidaudio_model_bundling.md` memory entry already documents one prior bundling-trap finding in this dependency, so it's a real surface.)
- **Tests directory not scanned.** The brief restricted scope to `Sources/`; per-test fixtures or integration harnesses might write audio, but they don't run in production.
- **Resources directory.** `Sources/PersonalScribeVAD/Resources/silero-vad.mlmodelc/` is bundled binary; checked superficially (model.mil tensor dumps are CoreML graph definitions, not user data).
- **`PersonalScribeSession/Models/` selection-tier files.** Read partially. The model-selection layer doesn't touch audio buffers but does touch model paths; not in lane 7's scope.
- **`AppKit` UI layer** beyond About / Settings was not swept for env reads. Spot-checked greps returned no matches; not exhaustive.

---

**Summary:** Lane 7 is clean. Audio stays in-memory from microphone tap to FluidAudio inference call; no disk writes, no debug dumps, no log-side leakage. No hardcoded secrets, no auth tokens, no env-driven supply-chain hooks. The single env-var read is a documented dev-mode base-directory override. The only persisted user data is transcript text in a 0600-permission SQLite file under FileVault — by product design, not a defect.
