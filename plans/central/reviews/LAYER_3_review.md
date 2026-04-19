# Layer 3 Review

## Verdict
NEEDS REVISION

## Finding summary
- Major: 3
- Medium: 3
- Low: 0

## Findings by checklist item
1. FAIL — The required do-not-diverge paragraph is not verbatim at the top. `plans/central/LAYER_3_settings.md:1` replaces the master prompt’s exact paragraph from `plans/CENTRAL_LAYERS_PROMPT.md:13-16` with custom Layer 3-specific prose.
2. PARTIAL — The locked `Preference<Value: Codable & Sendable>` surface and the seven named migrations are present in `plans/central/LAYER_3_settings.md:1`, `plans/central/LAYER_3_settings.md:41`, `plans/central/LAYER_3_settings.md:53`, and `plans/central/LAYER_3_settings.md:96`, and the required `[QUESTION]` markers are preserved at `plans/central/LAYER_3_settings.md:141-145`. But the bullets are not restated verbatim, and `WindowTint` / `PillAppearance` are downgraded to conditional no-ops at `plans/central/LAYER_3_settings.md:102-103` and `plans/central/LAYER_3_settings.md:135`.
3. PASS — The plan consistently drops the `Seshat` prefix from keys without adding migration code: the top constraint says so at `plans/central/LAYER_3_settings.md:1`, the proposed-key audit is at `plans/central/LAYER_3_settings.md:20-26` and `plans/central/LAYER_3_settings.md:32-33`, and the target instances stay bare at `plans/central/LAYER_3_settings.md:53-61`.
4. PASS — No `PS` prefix is introduced. The proposed keys remain unprefixed bare names at `plans/central/LAYER_3_settings.md:53-61`, and no alternate prefixed namespace appears anywhere in the plan.
5. FAIL — The plan does not honor the master prompt’s three-stage execution structure. Stage 1 is correctly isolated to the new directory at `plans/central/LAYER_3_settings.md:39` and `plans/central/LAYER_3_settings.md:71-72`, but Stage 2 batches multiple consumers inside resolver-based steps at `plans/central/LAYER_3_settings.md:94-103` instead of doing one consumer per swap step as required by `plans/CENTRAL_LAYERS_PROMPT.md:44-46`, and Stage 3 creates a local delete commit at `plans/central/LAYER_3_settings.md:107-115` instead of deferring deletions to the global INDEX pass required by `plans/CENTRAL_LAYERS_PROMPT.md:50-54`.
6. PARTIAL — The validation section does contain specific `file:line` anchors for Stage 1 and Steps `3.2` through `3.9` at `plans/central/LAYER_3_settings.md:128-137`. But there is no dedicated validation bullet for Step `3.10`, and the checklist is global rather than per-step despite the master prompt requiring every step to have its own validation checklist (`plans/CENTRAL_LAYERS_PROMPT.md:17`, `plans/CENTRAL_LAYERS_PROMPT.md:132-149`).
7. PASS — The forbidden-duplicates audit is present and materially scoped. `plans/central/LAYER_3_settings.md:117-124` explicitly audits the existing typed-defaults helpers, `BaseDirectoryPath`, the reference-only theme settings, onboarding completion, build metadata, and `ActiveModelDescriptor` single ownership.
8. PASS — The Stage 1 collision rule is honored. The new code is confined to `Sources/SeshatCore/Preferences/` and matching tests at `plans/central/LAYER_3_settings.md:39` and `plans/central/LAYER_3_settings.md:71-72`, and the locked `Config.swift.testingBaseDirectoryOverride` seam is explicitly protected at `plans/central/LAYER_3_settings.md:1`, `plans/central/LAYER_3_settings.md:32`, and `plans/central/LAYER_3_settings.md:144`.
9. PASS — `[QUESTION]` markers are preserved and explicit at `plans/central/LAYER_3_settings.md:141-145`.
10. FAIL — The inter-layer contract is not consistent with Layer 6. Layer 3 records `ActiveModelDescriptor` as a future `String` preference at `plans/central/LAYER_3_settings.md:33` and reserves `Preference<String>(key: "ActiveModelDescriptor", ...)` at `plans/central/LAYER_3_settings.md:61`, but Layer 6 defines `ActiveModelDescriptor` as a `Codable` struct at `plans/central/LAYER_6_model_selection.md:47-54` and depends on Layer 3 providing `Preference<ActiveModelDescriptor>` at `plans/central/LAYER_6_model_selection.md:97` and `plans/central/LAYER_6_model_selection.md:110`. No separate Layer 8 `Preference<Value>` conflict was found; Layer 8 only parallelizes with Layer 3 Stage 1 at `plans/central/LAYER_8_metrics.md:78`.

## Cross-layer concerns
- Layer 1: no conflict found. Layer 3 correctly keeps onboarding completion out of scope at `plans/central/LAYER_3_settings.md:122`, and Layer 1 already owns the deletion of `SeshatOnboardingCompleted` / `OnboardingState.swift` at `plans/central/LAYER_1_permissions.md:52` and `plans/central/LAYER_1_permissions.md:201-212`.
- Layer 2: conflict. Layer 2 makes `AppConfig` the canonical owner of override plumbing at `plans/central/LAYER_2_storage.md:25`, `plans/central/LAYER_2_storage.md:45`, and `plans/central/LAYER_2_storage.md:65`, but Layer 3 still anchors the new base-directory preference on `SeshatConfig.baseDirectoryPathPreference` at `plans/central/LAYER_3_settings.md:58` and `plans/central/LAYER_3_settings.md:101`.
- Layer 4: no direct contract conflict found. Layer 4 explicitly uses a target-neutral `AppStoreVisibilityMode` mirror while Layer 3 is still in flight at `plans/central/LAYER_4_appstore.md:207-209`.
- Layer 5: sequencing concern. Layer 5 requires centralized `PasteMode` and `PasteRestoreDelay` from Layer 3 at `plans/central/LAYER_5_output.md:413-414`, but Layer 3’s Stage 2 swaps are resolver-batched at `plans/central/LAYER_3_settings.md:96-99` rather than consumer-batched, which weakens the revertability the master prompt wanted.
- Layer 6: direct conflict. Layer 3 reserves `ActiveModelDescriptor` as `Preference<String>` at `plans/central/LAYER_3_settings.md:61`, while Layer 6 expects persisted `Preference<ActiveModelDescriptor>` at `plans/central/LAYER_6_model_selection.md:97` and `plans/central/LAYER_6_model_selection.md:110`.
- Layer 7: no direct conflict found. Layer 7 only relies on Layer 3 Stage 1 availability and parallelization at `plans/central/LAYER_7_pipeline.md:105-106`.
- Layer 8: no conflict found. Layer 8 only notes Stage 1 parallelism with Layer 3 at `plans/central/LAYER_8_metrics.md:78`.
- Layer 9: no conflict found. Layer 9 only parallelizes Stage 1 with Layer 3 and does not claim settings ownership at `plans/central/LAYER_9_app_brand.md:17-19` and `plans/central/LAYER_9_app_brand.md:58-61`.

## Stale file:line citations
None found. The Layer 3 plan’s direct file:line citations still resolve against the current trunk files I spot-checked during this audit.
