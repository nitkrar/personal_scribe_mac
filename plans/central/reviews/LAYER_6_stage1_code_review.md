# Layer 6 — Model Selection, Stage 1 Code Review

## Verdict
APPROVED WITH FOLLOW-UPS. Stage 1 matches the plan's additive shape: the new selection contracts, built-in catalog, live service, and model-aware FluidAudio bridge all landed in new directories, while the legacy `.v2` load path and existing AppKit/Session consumers stayed untouched. I found two low-severity follow-ups: the public transcription boundary still traps on unsupported descriptors, and the explicit Session wrapper APIs for `isDownloaded` / `download` are not directly exercised by tests.

## Finding Counts
- Critical: 0
- High: 0
- Medium: 0
- Low: 2
- Nit: 0

## Findings

### Critical
None observed.

### High
None observed.

### Medium
None observed.

### Low

#### Unsupported descriptors still trap at the public transcription boundary
- **Title**: Unsupported descriptors still trap at the public transcription boundary
- **Location**: `plans/central/LAYER_6_model_selection.md:78-83`; `Sources/SeshatSession/Models/Selection/ModelBoundTranscriberProvider.transcriber(for:)`; `Sources/SeshatTranscription/Models/Selection/FluidAudioRuntimeVariant.swift:10-20`; `Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:18-35`
- **Observation**: The plan's error contract says invalid selections should surface `ModelSelectionError.unknownVoiceModelID(String)`. The runtime-variant mapper follows that contract by throwing `unknownVoiceModelID`, but the public `ModelAwareFluidAudioTranscriber` initializer immediately converts the failure into `preconditionFailure("Unsupported model descriptor: ...")`.
- **Impact**: The Stage 1 happy path through `DefaultModelService` is safe because it canonicalizes to `BuiltInModelCatalog` first, but any future caller that reaches `ModelBoundTranscriberProvider.transcriber(for:)` or the transcriber initializer with a stale/custom descriptor will crash the process instead of staying on the layer's recoverable error path.
- **Suggested follow-up**: Make unknown-descriptor rejection explicit and recoverable at the provider/transcriber boundary, or make the crashing initializer internal so only prevalidated catalog descriptors can construct the transcriber.

#### The explicit `isDownloaded` / `download` wrapper surface is still unverified
- **Title**: The explicit `isDownloaded` / `download` wrapper surface is still unverified
- **Location**: `plans/central/LAYER_6_model_selection.md:66-76`; `Sources/SeshatSession/Models/Selection/DefaultModelService.isDownloaded(_:)`; `Sources/SeshatSession/Models/Selection/DefaultModelService.download(_:)`; `Sources/SeshatSession/Models/Selection/ModelBoundTranscriberProvider.isDownloaded(_:)`; `Sources/SeshatSession/Models/Selection/ModelBoundTranscriberProvider.download(_:)`; contrasted with `Tests/SeshatSessionTests/Models/Selection/DefaultModelServiceTests.swift:19-147` and `Tests/SeshatSessionTests/Models/Selection/ModelBoundTranscriberProviderTests.swift:7-84`
- **Observation**: Stage 1 exposes `isDownloaded` and `download` as first-class API on `ModelService`, and the provider contains matching wrappers, but the landed Session tests only exercise fallback resolution, `setActiveVoiceModel(_:)` auto-download, and transcriber caching. There is no direct assertion that the wrapper methods canonicalize IDs, return `false` for unknown descriptors, or pass download progress through unchanged.
- **Impact**: The implementation reads correctly by inspection, but two of the Stage 1 correctness surfaces called out in the review brief remain unverified by automated coverage and can regress silently.
- **Suggested follow-up**: Add focused Session tests that call the wrapper methods directly and assert unknown-ID behavior, canonical descriptor passthrough, on-disk path checks, and progress callback forwarding.

### Nit
None observed.

## Cross-Layer Concerns
- Layer 2 storage dep: `ModelBoundTranscriberProvider.modelDirectory(for:)` (`Sources/SeshatSession/Models/Selection/ModelBoundTranscriberProvider.swift:63-68`) and `ModelAwareFluidAudioTranscriber.modelDirectory()` (`Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:214-221`) both resolve `ManagedDirectory.models` through `StorageLocator` (`Sources/SeshatCore/Storage/StorageLocator.swift:3-7`, `Sources/SeshatCore/Storage/ManagedDirectory.swift:3-12`). No direct `SeshatConfig.directory(for:)` dependency was added in the new layer.
- Layer 3 preference dep: `DefaultModelService` persists through `Preference<ActiveModelDescriptor>` (`Sources/SeshatSession/Models/Selection/DefaultModelService.swift:12,20-43,85-86,132-159`) and the round-trip is covered in `Tests/SeshatCoreTests/Models/Selection/ActiveModelDescriptorTests.swift:28-44`. No direct `UserDefaults.standard.*` read/write appears in the new model-selection code; `UserDefaults` only enters via injected/defaulted constructors and the `Preference` wrapper.
- Any other layer touchpoints: Stage 1 intentionally leaves `SessionCoordinator`, `AppComposition`, `FluidAudioInferenceClient`, and the existing AppKit settings/onboarding surfaces on the legacy single-model path (`Sources/SeshatSession/SessionCoordinator.swift:28-38,103-113`, `Sources/SeshatAppKit/Composition/AppComposition.swift:10-25`, `Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27`, `Sources/SeshatAppKit/Settings/AIModelsTab.swift:8-45`, `Sources/SeshatAppKit/Settings/ModesTab.swift:17-43`, `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:122-124`), which matches the Stage 1 additive-only boundary. The already-tracked v3 placeholder / v2 default state is present in `Sources/SeshatCore/Models/Selection/BuiltInModelCatalog.swift:31-53` and was not counted as a new finding.

## Test Coverage Gaps
- Core: `Tests/SeshatCoreTests/Models/Selection/ActiveModelDescriptorTests.swift:16-44` and `Tests/SeshatCoreTests/Models/Selection/BuiltInModelCatalogTests.swift:5-41` cover happy-path codable/catalog composition, but there is no direct negative-path coverage for `BuiltInModelCatalog.descriptor(for:)` misses or `TranscriptionEngine+Codable` decoding.
- Session: `Tests/SeshatSessionTests/Models/Selection/DefaultModelServiceTests.swift:19-147` does not call `DefaultModelService.isDownloaded(_:)` or `DefaultModelService.download(_:)` directly, and `Tests/SeshatSessionTests/Models/Selection/ModelBoundTranscriberProviderTests.swift:7-84` does not cover the provider's `isDownloaded(_:)` / `download(_:)` helpers.
- Transcription: `Tests/SeshatTranscriptionTests/Models/Selection/ModelAwareTranscriberTests.swift:7-346` covers runtime mapping, retry, failure reset, and prepare deduplication, but not the standalone `download(progress:)` API or the `transcribe(_:)` / `transcribe(stream:)` success and error mapping paths.

## Stage-1 Scope Check
- Did Stage 1 avoid migrating `FluidAudioInferenceClient.loadModel(from:)`? yes. The legacy client still hardcodes `AsrModels.load(... version: .v2)` in `Sources/SeshatTranscription/FluidAudioInferenceClient.swift:25-27`, while the new runtime-mapped load path is additive in `Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioInferenceClient.swift:24-33`.
- Did Stage 1 avoid shipping a UI picker? yes. Existing AppKit surfaces remain read-only / string-based: `Sources/SeshatAppKit/Settings/AIModelsTab.swift:16-45`, `Sources/SeshatAppKit/Settings/ModesTab.swift:17-43`, `Sources/SeshatAppKit/Components/ModeCard.swift:15-110`, and `Sources/SeshatAppKit/Onboarding/OnboardingView.swift:122-124` still use the legacy single-model presentation.
- Any accidental Stage-2 creep? no. `23725ce` added new selection files plus `Tests/SeshatAppKitTests/Models/Selection/FakeModelService.swift:5-72` as isolated test support, and the Layer 6 hunks in `5a2ea99` were limited to a convenience initializer in `Sources/SeshatSession/Models/Selection/DefaultModelService.swift:20-43` and an explicit closure capture in `Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:224-259`.

## Summary
Plan fidelity is strong: `ActiveModelDescriptor`, `ModelService`, `BuiltInModelCatalog`, `DefaultModelService`, and the model-aware FluidAudio adapter/refactor all landed where the Layer 6 plan said they should, and the catalog contains v2, 110m, and the already-tracked v3 placeholder entry. Registry lookup, storage/preference round-trip, Stage 1 scope boundaries, and the `@MainActor` / actor / `Sendable` split all look sound from the code I read, and I did not see unexpected consumer migration or a premature UI picker. The main blockers before Stage 2 are small but concrete: remove the crash-on-unknown-descriptor edge at the public transcriber boundary and add direct tests for the explicit `isDownloaded` / `download` wrapper APIs. Main session should keep the tracked v3 placeholder/default-v2 follow-up separate when the pinned v3 metadata arrives.
