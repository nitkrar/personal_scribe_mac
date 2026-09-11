# #090 — Per-mode descriptor pinning — pre-spin investigation

**Author**: Claude (main session, 2026-04-29)
**Scope**: descriptor pinning only. Language hint is explicitly deferred per user direction; documented here as out-of-scope.
**Purpose**: surface architectural conflicts, audit existing seams, propose implementation shape, list TDD-driveable test cases — for codex review before drafting the plan.

---

## 1. What #090 (descriptor-pinning slice) needs

Functional outcome: a `WorkflowMode` can pin a specific `ModelDescriptor` for each of its transcriber processors. When pinned, `RecipeBuilder` resolves the pinned descriptor regardless of `ActiveModelService.activeDescriptor(for:)`. When unpinned (the default), late-bind to the globally-active descriptor (today's behavior).

UI outcome: in the Modes editor mode-detail screen, the "Voice model" row flips from a static label ("Manage in AI Models tab") to a picker that defaults to "Use globally active" and lists registered descriptors of the relevant kind.

---

## 2. Architectural invariant collision (now resolved)

**`Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift:5-11`** doc-comment:

> `ProcessorSpec` cases reference `ModelKind` — **never** a specific `ModelDescriptor.id` (per L23). Runtime late-binds the spec to the active descriptor for the named Kind via `ActiveModelService.activeDescriptor(for:)` at session start (eager, per L25). Recipes survive model swaps: changing the active ASR model in the AI Models tab updates the bound descriptor on the next session without rewriting the recipe.

**`Tests/PersonalScribeCoreTests/WorkflowMode/SpecCodableTests.swift:23-42`** lock test:

```swift
func testProcessorSpecReferencesKindNotDescriptorID() throws {
    // L23 lock: recipes reference `ModelKind`, never a specific
    // descriptor.id. ...
    XCTAssertNil(json?["descriptorID"], "ProcessorSpec must not carry a descriptor identifier — recipes late-bind via Kind (L23).")
    XCTAssertNil(json?["modelID"], "...")
}
```

**Resolution (per user, 2026-04-29):** L23 was always a first-pass lock. The original #078 design intent was to add per-mode model selection in a follow-up step (#090). Treating L23 as canonical now would silently dodge a planned follow-up. The L23 doc-comment + lock test are **expected to be updated** as part of this work, not preserved.

**New invariant** (revised L23): "Kind drives late-bind by default. An explicit per-spec `descriptorID` overrides late-bind and pins the spec to that descriptor. The `descriptorID`, when present, must reference a registered descriptor whose `kind` matches the spec's `kind`."

**Therefore:** Option A (extend `ProcessorSpec` cases with `descriptorID: String?`) is the path. Option B (sidecar map on `WorkflowMode`) and Option C (`Parameter<String?>` on the spec) were considered to dodge L23 and are no longer needed.

---

## 3. Pre-spin grep — what already exists

Per `feedback_pre_spin_grep.md`: I greppped for `descriptorID` and the `Parameter<T>` / `Override<T>` pattern *before* drafting.

**`descriptorID: String` already exists** in two non-recipe places — distinct concept, no naming clash:

- `Sources/PersonalScribeSession/Models/Selection/AdapterRecord.swift:5` — adapter cache key (which descriptor produced this `AdapterRecord`).
- `Sources/PersonalScribeSession/Models/Selection/ModelBoundProcessorProvider.swift:7,17,24` — registry key for `registeredDescriptorsByID: [String: ModelDescriptor]`.

These are adapter-side identity, not a recipe-side override. Re-using the name `descriptorID` on `ProcessorSpec` is consistent — same concept (the descriptor's `id: String`), different role (recipe-side pin vs. adapter-side cache key).

**`Parameter<Value>` already exists** at `Sources/PersonalScribeCore/WorkflowMode/Parameter.swift:37-40` with `.setting(SettingKey<Value>) | .override(Value)` and a `ParameterResolver` cascade.

I considered modeling the pin as `Parameter<String?>` (`.setting` = late-bind, `.override` = pin). Rejected: there is no `SettingKey` here. The "default" path is "late-bind to active", not "read a UserDefaults scalar". Wrapping `String?` in `Parameter` would force a synthetic `SettingKey` whose only resolution semantics are "ignore me, ask `ActiveModelService` instead" — which is exactly the synonym/over-engineering trap the memory rule warned about. Bare `String?` is correct.

**`ModelDescriptor.id` is `String`** (`Sources/PersonalScribeCore/Models/Selection/ModelDescriptor.swift:100`). No nominal `ID` typealias — the field type is plain `String`. Adding a typealias is out of scope.

---

## 4. Late-bind seam — single injection point

`Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift:105-110`:

```swift
private func resolveDescriptor(for kind: ModelKind) throws -> ModelDescriptor {
    guard let descriptor = modelService.activeDescriptor(for: kind) else {
        throw RecipeBuildError.kindHasNoActiveDescriptor(kind)
    }
    return descriptor
}
```

This is the unique site where `ModelKind → ModelDescriptor` happens in the recipe-build path. Three callers in `buildProcessor`:
- `.transcriber(let kind)` — line 54
- `.streamingTranscriber(let kind)` — line 59
- `.diarizedTurns(let diarizerKind, let transcriberKind)` — lines 64-66 (two resolves)

**Plumbing change**: `resolveDescriptor` becomes `resolveDescriptor(for kind: ModelKind, descriptorID: String?)`. Pin-aware path: if `descriptorID` is non-nil, look it up in `registeredModels` and validate `kind` matches; fall back to today's behavior on nil.

**Note**: the `.diarizedTurns` case has *two* descriptor resolves (diarizer + transcriber). #090's pinning slice should pin both legs independently — diarizer pin and transcriber pin are separate fields on the case.

---

## 5. UI seam — anticipated by #089

`Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift:92-114`:

```swift
private var voiceModelCard: some View {
    SettingsCard {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading) {
                Text("Voice model")...
                Text(activeVoiceModelDescription)...
            }
            // #090 picks up per-mode override; for now the row is
            // read-only and points the user at AI Models.
            Text("Manage in AI Models tab")...
        }
    }
}
```

The hook is anticipated. #089 left a comment marking exactly where the picker goes. Need to:
- Replace the static "Manage in AI Models tab" label with a `Menu` (or `Picker`).
- First entry: "Use globally active (\(currentActiveDisplayName))".
- Subsequent entries: registered descriptors of the relevant kind (filtered via `modelService.enabledModels(kind:)`).
- Selection writes through `ModeDetailViewModel.setVoiceModelPin(_)` → `WorkflowMode.withVoiceModelPin(_)` mutator → `registry.saveCustom(...)`.

**Mutator pattern**: extend `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeRecipeMutators.swift`. The existing mutators all consume the first `ProcessorSpec` of the matching shape; the new mutator follows the same convention. (Open question §7-A: does anything in the app produce `WorkflowMode`s with multiple `.transcriber` specs? Modes editor today produces at most one transcriber + optional diarizer, so the "first match" pattern is fine for V1.)

---

## 6. Implementation shape (Option A direct extension)

### 6.1 `ProcessorSpec` (Core)

```swift
public enum ProcessorSpec: Codable, Equatable, Sendable {
    case transcriber(kind: ModelKind, descriptorID: String? = nil)
    case streamingTranscriber(kind: ModelKind, descriptorID: String? = nil)
    case diarizedTurns(
        diarizerKind: ModelKind,
        diarizerDescriptorID: String? = nil,
        transcriberKind: ModelKind,
        transcriberDescriptorID: String? = nil
    )
}
```

- Defaulted to `nil` so all existing call sites in tests + `WorkflowMode.dictation` compile unchanged.
- Codable: `descriptorID` (or `diarizerDescriptorID` / `transcriberDescriptorID`) becomes an optional decoded field. Decode tolerates absence (nil) and presence. Old documents (no key) round-trip back as nil.
- The L23 lock test gets rewritten to a positive form: a new `testProcessorSpecCarriesDescriptorIDOverride` asserts encoded JSON includes `descriptorID` only when set; round-trip of a pinned spec preserves it.

### 6.2 `WorkflowModeValidator`

Add a rule: when a processor spec carries `descriptorID`, it must reference a descriptor in the supplied `availableKinds`-context registry, and that descriptor's `kind` must match the spec's `kind`. The validator currently takes `availableKinds: Set<ModelKind>`; we'll need to extend its inputs to receive the registered descriptor list (or a closure that resolves id → kind). Cleanest: pass `registeredDescriptors: [ModelDescriptor]` alongside `availableKinds`. Existing call sites are: registry save, `RecipeBuilder.build`, `SessionCoordinator` — all have access to `BuiltInModelCatalog.registeredModels` or `ActiveModelService.registeredModels`.

Two new error cases:

```swift
case pinnedDescriptorNotRegistered(id: String)
case pinnedDescriptorKindMismatch(id: String, expected: ModelKind, actual: ModelKind)
```

### 6.3 `RecipeBuilder`

```swift
private func resolveDescriptor(
    for kind: ModelKind,
    pinnedID: String?
) throws -> ModelDescriptor {
    if let pinnedID {
        guard let pinned = modelService.registeredModels.first(where: { $0.id == pinnedID }) else {
            throw RecipeBuildError.pinnedDescriptorNotRegistered(id: pinnedID)
        }
        guard pinned.kind == kind else {
            throw RecipeBuildError.pinnedDescriptorKindMismatch(id: pinnedID, expected: kind, actual: pinned.kind)
        }
        return pinned
    }
    guard let descriptor = modelService.activeDescriptor(for: kind) else {
        throw RecipeBuildError.kindHasNoActiveDescriptor(kind)
    }
    return descriptor
}
```

Note: this routes pinned through `modelService.registeredModels` rather than `BuiltInModelCatalog.registeredModels` directly so test fixtures that inject custom registered model lists into `ActiveModelService` see the same view.

### 6.4 Modes editor UI

`ModeDetailViewModel`:
- New computed property `voiceModelPinID: String?` reads the first transcriber/streaming-transcriber spec's `descriptorID`.
- New setter `setVoiceModelPin(_ id: String?)` calls `mode.withVoiceModelPin(id)`.

`ModeRecipeMutators`:
- New extension method `withVoiceModelPin(_ id: String?) -> WorkflowMode` rewrites the first matching transcriber/streaming-transcriber spec.

`ModeDetailView.voiceModelCard`:
- Replace the read-only label with a `Menu` styled to match other rows.
- Items: "Use globally active (\(activeDisplayName))" (writes nil) + one item per `modelService.enabledModels(kind: kind)` (writes that descriptor's id).
- `kind` is `realtimeOn ? .streamingASR : .asr`.

### 6.5 Diarizer pin (open question §7-B)

The diarizer leg of `.diarizedTurns` could also be pinnable, but today only one diarizer descriptor exists (`speaker-diarization`). Picker has nothing to choose from. **Recommendation**: include the schema field (`diarizerDescriptorID: String?`) for future-proofing — the cost is one extra optional in the Codable shape — but **do not surface a diarizer picker in the UI for V1**. Open: confirm with user.

---

## 7. Open design questions (need user adjudication or codex sanity-check)

**7-A. Multiple transcriber specs in one mode.** The mutator pattern assumes "first match". Does any built-in or custom mode produce multiple `.transcriber` specs? Today's `WorkflowMode.dictation` has one. The modes editor produces at most one transcriber + optional diarizer. Confirm: for V1, "first match" mutator is sufficient.

**7-B. Diarizer picker in V1?** Schema-yes, UI-no is the sketch in §6.5. Confirm.

**7-C. `enabledModels(kind:)` filter — is `isEnabled = false` excluded from the picker?** `BuiltInModelCatalog.qwen3AsrF32` and `qwen3AsrInt8` are `isEnabled: false` today. `ActiveModelService.enabledModels` filters them out, so the picker won't list them. Is that the desired behavior, or should the picker include disabled descriptors and show them greyed-out? Implication: if Qwen is disabled and the user has no way to pin to it, that contradicts the eventual #090 vision. Recommendation: respect `isEnabled` for V1 (no greyed-out rows) — the user re-enables Qwen via separate work before pinning becomes useful for it.

**7-D. Persistence of stale pins.** If the user deletes a registered descriptor (or it's removed from the catalog in a future build), modes that pinned it would silently fail validation at session start. Today's behavior for invalid `activeModelIDs[kind]` is to log + prune (`ActiveModelService.resolveInitialActiveIDs` line 423). Should pinned mode `descriptorID`s also auto-prune on registry save, or fail loudly? Recommendation: validator throws at save time so the user gets immediate feedback; pruning at session-start would silently lose intent.

**7-E. Where does the validator get the registered descriptor list?** Today `WorkflowModeValidator.validate` takes `availableKinds: Set<ModelKind>`. Adding `registeredDescriptors: [ModelDescriptor]` to the signature is a breaking change to a public API. Three call sites need updating (registry save, `RecipeBuilder.build`, `SessionCoordinator`). Acceptable.

---

## 8. TDD plan (vertical, not bulk)

Per project CLAUDE.md "Rigid TDD for logic, protocols, state machines": one failing test → minimal code → repeat. **Not** all tests then all code.

Order matters — validator tests first because the validator is the source of truth for the new invariant:

1. **`WorkflowModeValidatorTests.testPinnedDescriptorMustBeRegistered`** — fails with old validator signature (which doesn't know about pins). Add the new error case + minimal validator path.
2. **`WorkflowModeValidatorTests.testPinnedDescriptorKindMustMatchSpecKind`** — covers the kind-mismatch case.
3. **`WorkflowModeValidatorTests.testUnpinnedSpecValidatesAsBefore`** — regression rail; ensures Option A's default = late-bind didn't break existing modes.
4. **`SpecCodableTests`** — *replace* `testProcessorSpecReferencesKindNotDescriptorID` with `testProcessorSpecCarriesDescriptorIDOverride` (positive form). Round-trip `.transcriber(kind: .asr, descriptorID: "parakeet-tdt-0.6b-v2")` and assert `descriptorID` is present in the JSON. Round-trip `.transcriber(kind: .asr)` and assert `descriptorID` is absent.
5. **`RecipeBuilderTests.testPinnedDescriptorOverridesActive`** — fails until `RecipeBuilder.resolveDescriptor` consults the pin.
6. **`RecipeBuilderTests.testUnpinnedFallsBackToActive`** — regression rail.
7. **`RecipeBuilderTests.testPinnedDescriptorThrowsWhenNotRegistered`** — error-path coverage.
8. **`ModeDetailViewModelTests.testVoiceModelPinSetter`** — view-model setter writes through to the mode.
9. UI: per project CLAUDE.md flexible-TDD discipline, the SwiftUI Menu can't be XCTest'd directly. Add a manual-verification entry to `Tests/PersonalScribeAppKitTests/Manual*Verification.md` (the runbook for the Modes editor — TBD which file).

Estimated commits: 5-8 (one per TDD cycle), staged as a single `phase-3 step #090: per-mode descriptor pinning` series.

---

## 9. Files in scope (semantic inventory)

**Core**:
- `Sources/PersonalScribeCore/WorkflowMode/ProcessorSpec.swift` — schema + Codable
- `Sources/PersonalScribeCore/WorkflowMode/WorkflowModeValidator.swift` — pin validation rules + new error cases

**Session**:
- `Sources/PersonalScribeSession/WorkflowMode/RecipeBuilder.swift` — `resolveDescriptor` consults pin
- (No change to `BoundRecipe.swift` — bound recipe holds resolved adapters, doesn't carry the spec-level pin downstream)

**AppKit**:
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailView.swift` — voiceModelCard becomes a picker
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeDetailViewModel.swift` — pin getter + setter
- `Sources/PersonalScribeAppKit/UnifiedWindow/Tabs/Modes/ModeRecipeMutators.swift` — `withVoiceModelPin`

**Tests**:
- `Tests/PersonalScribeCoreTests/WorkflowMode/SpecCodableTests.swift` — replace L23 lock test
- `Tests/PersonalScribeCoreTests/WorkflowMode/WorkflowModeValidatorTests.swift` — new pin rules
- `Tests/PersonalScribeSessionTests/WorkflowMode/RecipeBuilderTests.swift` — new pin paths
- `Tests/PersonalScribeAppKitTests/...` — view-model tests (file may need to be created)

**Out of scope**:
- Language hint plumbing (deferred per user)
- `supportedLanguages` on `ModelDescriptor` (deferred)
- Qwen3 re-enablement / memory re-validation (independent — and the pinning UI skips disabled descriptors per §7-C)
- `BoundRecipe` shape changes
- Anything in the AI Models tab

---

## 10. What I want codex to review

Specific questions for codex (in priority order):

1. **Soundness of Option A direct extension** — given L23 was first-pass and is being rewritten, is `descriptorID: String?` defaulted-nil on each case the right shape? Or is there a cleaner factoring (e.g. extracting a shared `TranscriberRef` struct)?
2. **Diarizer pin schema-yes / UI-no** (§6.5) — does codex see future shape concerns with stubbing `diarizerDescriptorID: String?` now even though no UI surfaces it?
3. **Validator signature change** (§7-E) — `registeredDescriptors: [ModelDescriptor]` added to `WorkflowModeValidator.validate`. Three call sites. Any cleaner injection?
4. **Mutator "first match" pattern** (§7-A) — sufficient for V1, or should the mutator address all transcriber specs?
5. **Disabled-descriptor filter** (§7-C) — agree with "respect `isEnabled` in the picker"?
6. **Stale-pin handling** (§7-D) — agree validator throws at save time over silent prune at session start?
7. **TDD order** (§8) — does the proposed sequence have the right dependencies, or is there a hidden ordering bug?
8. **Anything I missed** — entire file is in scope for cross-checks. Any consumer of `ProcessorSpec` cases I haven't enumerated?

Codex output → `plans/investigations/2026-04-29-090-descriptor-pinning-codex.md`.
