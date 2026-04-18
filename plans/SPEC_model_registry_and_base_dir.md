# Spec: Model Registry + Configurable Base Directory

**Status:** Ready to implement
**Scope:** Phase 1 (resolve-only, no migration). Migration lands later with Settings UI.
**Estimated files:** 1 new, 3 modified.

## Motivation

1. **Multi-model support.** Current code hardcodes `parakeet-tdt-0.6b-v2` in three places (`Config.swift:6`, `FluidAudioModelDownloader.swift:5-7`, `FluidAudioTranscriber.swift:44-48`). Adding a second model (e.g. `parakeet-tdt-110m` for lower-RAM devices) requires parallel editing + drift risk.
2. **Configurable storage root.** Users who want their models under `~/Documents/Seshat/` (superwhisper-style, user-visible in Finder, persists outside app cleanup tools) should be able to override the default. All persistent state — models, modes, future recordings — must live under a single root so override is one setting, not N.

## Non-goals (explicit)

- **Not building migration this pass.** Changing the base at runtime and moving existing content lands when the Settings UI ships. For now, override is read at startup and never changes.
- **Not building the modes/ or recordings/ features.** Just reserving the directory structure so future work doesn't retouch `SeshatConfig`.
- **No UI.** Override is set via UserDefaults or env var only.
- **No backward-compat migration for existing `~/Library/Application Support/Seshat/Seshat/` double-nesting bug if any.** Check `Config.swift:40` — base is `<applicationSupportDirectory>/Seshat/`, which is correct; flag if you spot drift.

## Target layout

```
<base>/                              # default: ~/Library/Application Support/Seshat/
                                     # override examples:
                                     #   ~/Documents/Seshat/
                                     #   /Volumes/External/Seshat/
  models/
    parakeet-tdt-0.6b-v2/           # existing
    parakeet-tdt-110m/              # future
  modes/                             # future — transcription profiles as JSON
  recordings/                        # future — if we retain raw audio
```

## File 1 (NEW): `Sources/SeshatCore/ModelRegistry.swift`

```swift
import Foundation

public enum TranscriptionEngine: Sendable, Equatable {
    case parakeetTDT
    // Reserve shape for future engines (parakeetCTC, whisper, etc.).
    // Do not implement them now.
}

public struct ModelDescriptor: Sendable, Equatable {
    public let id: String                  // "parakeet-tdt-0.6b-v2" — also the on-disk directory name
    public let displayName: String         // "Parakeet TDT 0.6B" — surfaces in future Settings UI
    public let repository: String          // HuggingFace repo, e.g. "FluidInference/parakeet-tdt-0.6b-v2-coreml"
    public let revision: String            // pinned commit SHA
    public let requiredRelativePaths: [String]  // artifacts inside the repo to fetch
    public let approximateSizeBytes: Int64 // for display and disk-space checks
    public let engine: TranscriptionEngine

    public func resolveURL(for relativePath: String) -> URL {
        URL(
            string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(relativePath)"
        )!
    }
}

public enum ModelRegistry {
    public static let parakeetTDT06Bv2 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v2",
        displayName: "Parakeet TDT 0.6B",
        repository: "FluidInference/parakeet-tdt-0.6b-v2-coreml",
        revision: "ee09c569f73759e6d44c9bd16766f477b2b36d39",
        requiredRelativePaths: [
            "Preprocessor.mlmodelc/coremldata.bin",
            "Encoder.mlmodelc/coremldata.bin",
            "Decoder.mlmodelc/coremldata.bin",
            "JointDecision.mlmodelc/coremldata.bin",
            "parakeet_vocab.json",
        ],
        approximateSizeBytes: 450_000_000,
        engine: .parakeetTDT
    )

    // Reserve slot. Do not populate until user asks.
    // public static let parakeetTDT110M = ...

    public static let all: [ModelDescriptor] = [parakeetTDT06Bv2]

    public static func descriptor(for id: String) -> ModelDescriptor? {
        all.first { $0.id == id }
    }

    public static let defaultModelId: String = parakeetTDT06Bv2.id
}
```

**Acceptance:** registry compiles, `descriptor(for:)` returns expected descriptor for the current model id, `defaultModelId` matches existing behavior.

## File 2 (MODIFY): `Sources/SeshatCore/Config.swift`

Replace the current implementation with:

```swift
import Foundation

public enum SeshatConfig {
    public static let sampleRate: Double = 16_000
    public static let channelCount: Int = 1

    // DEPRECATED shim — keeps existing callers compiling.
    // Prefer ModelRegistry.defaultModelId and ModelDescriptor throughout new code.
    public static let modelId: String = ModelRegistry.defaultModelId

    // MARK: - Base directory resolution

    /// Resolution order (first match wins):
    ///   1. `SESHAT_BASE_DIR` environment variable (dev/test convenience)
    ///   2. `SeshatBaseDirectoryPath` UserDefaults key (user-facing override)
    ///   3. `~/Library/Application Support/Seshat/` (default)
    ///
    /// `testingBaseDirectoryOverride` takes precedence over all three for XCTest.
    public static func baseDirectory() throws -> URL {
        try directoryLock.withLock {
            let directory = resolvedBaseDirectory()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            return directory.standardizedFileURL
        }
    }

    public static func modelsDirectory() throws -> URL {
        try subdirectory(named: "models")
    }

    /// Reserved for future modes/ feature. Directory is created lazily.
    public static func modesDirectory() throws -> URL {
        try subdirectory(named: "modes")
    }

    /// Reserved for future recordings/ feature. Directory is created lazily.
    public static func recordingsDirectory() throws -> URL {
        try subdirectory(named: "recordings")
    }

    /// Directory for a specific model's artifacts.
    public static func directory(for descriptor: ModelDescriptor) throws -> URL {
        let models = try modelsDirectory()
        let directory = models.appendingPathComponent(descriptor.id, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - Legacy / test support

    // Plan 00 D.1: test code mutates this from XCTest's default single-threaded path only.
    public nonisolated(unsafe) static var testingBaseDirectoryOverride: URL?

    // MARK: - Private

    private static let directoryLock = NSLock()
    private static let userDefaultsKey = "SeshatBaseDirectoryPath"
    private static let envVarName = "SESHAT_BASE_DIR"

    private static func subdirectory(named name: String) throws -> URL {
        let base = try baseDirectory()
        let directory = base.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func resolvedBaseDirectory() -> URL {
        if let override = testingBaseDirectoryOverride {
            return override.appendingPathComponent("Seshat", isDirectory: true).standardizedFileURL
        }

        if let envPath = ProcessInfo.processInfo.environment[envVarName], !envPath.isEmpty {
            return URL(fileURLWithPath: envPath, isDirectory: true).standardizedFileURL
        }

        if let userPath = UserDefaults.standard.string(forKey: userDefaultsKey), !userPath.isEmpty {
            return URL(fileURLWithPath: userPath, isDirectory: true).standardizedFileURL
        }

        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return appSupport.appendingPathComponent("Seshat", isDirectory: true).standardizedFileURL
    }
}
```

**Key semantics:**
- `testingBaseDirectoryOverride` still nests a `Seshat/` folder (preserves current test behavior).
- Env var + UserDefaults paths are used **as-is** (the user's chosen path IS the base). If a user sets `SeshatBaseDirectoryPath = /Users/nitin/Documents/Seshat`, that's the full base. Don't append `Seshat/` again.
- Keep `appSupportDirectory()` public signature? **Remove** — callers should use `baseDirectory()`. Grep and update call sites.

**Acceptance:**
- Default path unchanged: `~/Library/Application Support/Seshat/`.
- `SESHAT_BASE_DIR=/tmp/foo swift test` places state under `/tmp/foo/models/...`.
- `defaults write com.nitkrar.seshat SeshatBaseDirectoryPath ~/Documents/Seshat` is respected on next app launch.
- `XCTest` tests using `testingBaseDirectoryOverride` still pass without modification.

## File 3 (MODIFY): `Sources/SeshatTranscription/FluidAudioModelDownloader.swift`

Delete `enum ParakeetArtifact`. Replace with a descriptor-driven downloader:

```swift
import Foundation
import SeshatCore

internal struct PrivateModelDownloader: ModelDownloading {
    private let descriptor: ModelDescriptor
    private let session: URLSession = .shared
    private let clock = ContinuousClock()

    init(descriptor: ModelDescriptor) {
        self.descriptor = descriptor
    }

    func ensureModelAvailable(
        at directory: URL,
        progress: @escaping @Sendable (ModelDownloadProgress) -> Void
    ) async throws -> URL {
        // ... same logic as before, but replace every `ParakeetArtifact.X` with
        // `descriptor.X` and use `descriptor.resolveURL(for:)`.
        // The stagingDirectory derivation still uses
        //   FluidAudioTranscriber.stagingDirectory(base: directory.deletingLastPathComponent(), descriptor: descriptor)
        // so staging and final are co-located under the same models/ parent.
    }
}
```

**Acceptance:** downloader behaves identically for the existing parakeet model. Swapping `descriptor` to a hypothetical second model changes only the URL/filename set, not the logic.

## File 4 (MODIFY): `Sources/SeshatTranscription/FluidAudioTranscriber.swift`

- `FluidAudioTranscriber.init` now takes a `descriptor: ModelDescriptor = ModelRegistry.parakeetTDT06Bv2` parameter (default keeps call sites working).
- Replace hardcoded `ParakeetArtifact.modelDirectoryName` / `requiredRelativePaths` references with `descriptor.id` / `descriptor.requiredRelativePaths`.
- Directory helpers become descriptor-aware:
  - `modelDirectory()` → `try SeshatConfig.directory(for: descriptor)`
  - `stagingDirectory(base:)` → `stagingDirectory(base:descriptor:)` so the `-staging` suffix is scoped to the descriptor's id (`"\(descriptor.id)-staging"`).
- `parakeet_vocab.json` reference at line 290 — pull from descriptor's required paths or leave as-is (vocab filename is stable per engine; acceptable to keep).

**`PrivateFluidAudioInferenceClient`:** if it currently reaches for `ParakeetArtifact`, pass the descriptor in its init too. If it doesn't, no change needed.

**Acceptance:** existing tests pass without modification. `FluidAudioTranscriber()` with no args behaves exactly as before.

## Test updates

1. **No new tests required** for happy-path (existing integration covers it — descriptor default keeps behavior identical).
2. **Add one unit test** in `SeshatCoreTests`:
   - `SeshatConfigTests.testEnvVarOverridesBase` — set `SESHAT_BASE_DIR`, assert `baseDirectory()` returns that path.
   - `SeshatConfigTests.testUserDefaultsOverride` — set UserDefaults key, assert override, clean up.
   - `ModelRegistryTests.testDescriptorLookup` — `descriptor(for:)` round-trip.

## Out of scope (do NOT implement this pass)

- `BaseDirectoryMigrator` — moving content when base changes.
- Settings UI for selecting base directory.
- A second model descriptor populated in the registry.
- Making `SeshatConfig.modelId` a user-changeable setting.
- `modes/` JSON schema or loader.

## Ordering with in-flight Codex work

**Land the `Task.detached` + silent-catch + menu-bar fixes FIRST** (separate patch). This refactor should rebase on top of those fixes, not race with them. If the uncommitted `AppStartupCoordinator` / pill fixes are reverted, this spec still applies unchanged — it touches disjoint files (`Config.swift`, Transcription module, new Registry file).
