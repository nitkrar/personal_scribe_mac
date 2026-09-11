# 2026-04-26 Security Audit — Lane 7 Capture & secrets (Codex retry-2)

> **Provenance note:** This is the second retry of the Lane 7 Codex audit. Codex's sandbox was read-only — neither the heartbeat file nor the report file could be written from within the agent. Report content recovered verbatim from the agent's final assistant message by main session as a transcription artifact. The earlier two attempts (original dispatch + retry-1) wedged in the initial-read phase before producing draftable output.

## 1. Threat-model framing

This pass checked whether `Sources/` persists raw capture buffers, reads unexpected environment variables, embeds secrets, stores sensitive preference keys, or hardcodes unexpected outbound URLs. It does not assume derived content is non-persistent; transcript text persistence is separately called out below.

## 2. Files audited

- `plans/codex-heartbeat-contract.md`
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift`
- `Sources/PersonalScribeSession/WorkflowMode/WorkflowModeStore.swift`
- `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift`
- `Sources/PersonalScribeCore/Storage/AppConfig.swift`
- `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift`
- `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift`
- `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift`
- `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift`
- `Sources/PersonalScribeCore/PCMBuffer.swift`
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift`
- `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift`
- `Sources/PersonalScribeCore/AppBrand/AppBrand.swift`
- `Sources/PersonalScribeCore/Database/AppDatabase.swift`
- `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift`
- `Sources/PersonalScribeCore/Database/TranscriptRepository.swift`

## 3. Claim verdicts

1. **Audio-on-disk: CONFIRMED** — the grep only found writes of stub model artifacts (`Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:224-232`) and `workflow-modes.json` config (`Sources/PersonalScribeSession/WorkflowMode/WorkflowModeStore.swift:63-72`, schema at `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeDocument.swift:3-21`); no `AVAudioFile` matches were present in `Sources/`.
2. **Env reads scoped: CONFIRMED** — environment snapshots appear at `Sources/PersonalScribeCore/BaseDirectoryMigrator.swift:67`, `Sources/PersonalScribeCore/Storage/AppStorageLocator.swift:15`, and `Sources/PersonalScribeCore/Storage/AppConfig.swift:18,54`, and the only keyed lookup is `environment[baseDirectoryEnvironmentVariableName]` at `Sources/PersonalScribeCore/Storage/AppConfig.swift:101-102`, where the constant is `PERSONAL_SCRIBE_BASE_DIR` at `Sources/PersonalScribeCore/Storage/AppConfig.swift:10`.
3. **No hardcoded secrets: CONFIRMED** — the grep returned one match, `Sources/PersonalScribeTranscription/Adapters/FluidAudioParakeetTranscriberAdapter.swift:360`, which parses a model-output `"token"` field alongside `tokenTimings` labels at `:352`; there were no `Bearer`, `"api_key"`, `"secret"`, `KeychainAccess`, or `password` matches in `Sources/`.
4. **PreferenceKeys safe: CONFIRMED** — `Sources/PersonalScribeCore/Preferences/PreferenceKeys.swift` defines only `VadSilenceDurationSeconds` (`:20-23`), `VadShowStoppingWarning` (`:27-30`), `VadShowAutoStoppedNotification` (`:34-37`), and `ClipboardRestoreEnabled` (`:41-44`); none store transcript text, recording paths, or device IDs.
5. **PCMBuffer in-memory: CONFIRMED** — `Sources/PersonalScribeCore/PCMBuffer.swift:3-31` contains only in-memory fields (`samples`, `sampleRate`, `channelCount`, `timestamp`) plus derived accessors; there is no disk I/O or filesystem serialization.
6. **URLs scoped to HuggingFace+About: CONFIRMED** — the only URL strings in `Sources/` are the About link at `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/AboutSubTab.swift:84`, the HuggingFace download template at `Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:195`, and a doc-comment repeat of the mythology link at `Sources/PersonalScribeCore/AppBrand/AppBrand.swift:15`; no other domains were found.

## 4. Findings (only if any claim REFUTED or other concern)

- **Medium** — `Sources/PersonalScribeCore/Database/AppDatabase.swift:41-43`, `Sources/PersonalScribeCore/Database/Migrations/TranscriptsMigrator.swift:26-30`, `Sources/PersonalScribeCore/Database/TranscriptRepository.swift:55-59,96-101`, `Sources/PersonalScribeCore/Database/AppDatabase.swift:192-200`: transcript text is persisted to `<recordings>/transcripts.sqlite` with a `text` column and append/update write paths; this does not refute the raw-audio claim, but it is sensitive derived content on disk, so the project should document retention/deletion behavior and decide whether file mode `0600` is sufficient or whether stronger at-rest protection is required.

## 5. Coverage gaps

- This was a targeted read-only pass over `Sources/`; I did not inspect tests, generated artifacts, third-party dependencies, or runtime filesystem state.
- `Sources/PersonalScribeCore/Database/TranscriptRepository.swift:71-73` references future optional on-disk audio sidecars for ticket `#069`; no implementation was found in this pass, but future work there could change claim 1.
- The sandbox was read-only, so I could not write `.codex-heartbeat/sec-audit-7-capture-codex-retry-2.md` or the requested report file fallback; the audit evidence is therefore only in this message.
