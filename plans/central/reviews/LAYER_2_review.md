Verdict: NEEDS REVISION

Finding summary: critical 0 | major 4 | minor 2

| item # | pass/fail/partial | evidence citation |
|---|---|---|
| 1 | PASS | plans/CENTRAL_LAYERS_PROMPT.md:13-15; plans/central/LAYER_2_storage.md:1-6 |
| 2 | PARTIAL | plans/CENTRAL_LAYERS_PROMPT.md:186-202; plans/central/LAYER_2_storage.md:13-23; plans/central/LAYER_2_storage.md:42-58; plans/central/LAYER_2_storage.md:206-208 |
| 3 | PARTIAL | plans/CENTRAL_LAYERS_PROMPT.md:42-54; plans/CENTRAL_LAYERS_PROMPT.md:75-78; plans/central/LAYER_2_storage.md:69-173 |
| 4 | FAIL | plans/CENTRAL_LAYERS_PROMPT.md:11-17; plans/central/LAYER_2_storage.md:76-173; plans/central/LAYER_2_storage.md:186-201 |
| 5 | PARTIAL | plans/central/LAYER_2_storage.md:25; plans/central/LAYER_2_storage.md:45; plans/central/LAYER_2_storage.md:65; plans/central/LAYER_2_storage.md:105; plans/central/LAYER_2_storage.md:171-173; Sources/SeshatCore/Config.swift:3-63; Sources/SeshatCore/Storage/AppConfig.swift:3-65; Sources/SeshatCore/Storage/AppStorageLocator.swift:26-51 |
| 6 | FAIL | plans/CENTRAL_LAYERS_PROMPT.md:44-59; plans/central/LAYER_2_storage.md:22; plans/central/LAYER_2_storage.md:76-95; Sources/SeshatCore/Storage/ManagedDirectory.swift:1-13; Sources/SeshatCore/Storage/StorageLocator.swift:1-7; Sources/SeshatCore/Storage/AppStorageLocator.swift:1-52; Sources/SeshatCore/Storage/AppConfig.swift:1-65; Sources/SeshatCore/Storage/AtomicFileWriter.swift:1-8; Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift:1-69; Sources/SeshatCore/Storage/DiskSpaceSnapshot.swift:1-48; Tests/SeshatCoreTests/Storage/StorageLocatorTests.swift:5-145; Tests/SeshatCoreTests/Storage/AtomicFileWriterTests.swift:5-90; Tests/SeshatCoreTests/Storage/DiskSpaceSnapshotTests.swift:5-58; Tests/SeshatCoreTests/Storage/AppConfigTests.swift:5-65 |
| 7 | PASS | plans/central/LAYER_2_storage.md:61; plans/central/LAYER_2_storage.md:95 |
| 8 | PASS | plans/central/LAYER_2_storage.md:182-185 |
| 9 | PARTIAL | plans/CENTRAL_LAYERS_PROMPT.md:201-202; plans/central/LAYER_2_storage.md:206-208; plans/central/LAYER_3_settings.md:9-12; plans/central/LAYER_6_model_selection.md:95-97; plans/central/LAYER_6_model_selection.md:123; plans/central/LAYER_6_model_selection.md:247-249; plans/central/LAYER_7_pipeline.md:373-375; plans/central/LAYER_8_metrics.md:115; plans/central/LAYER_8_metrics.md:177-178 |
| 10 | PASS | plans/central/LAYER_2_storage.md:30-38; Sources/SeshatCore/Config.swift:13-106; Sources/SeshatCore/TranscriptStore.swift:30-75; Sources/SeshatCore/SQLiteTranscriptStore.swift:33-60; Sources/SeshatCore/SQLiteTranscriptStore.swift:204-229; Sources/SeshatCore/BaseDirectoryMigrator.swift:58-126; Sources/SeshatCore/BaseDirectoryMigrator.swift:174-193; Sources/SeshatAppKit/Settings/AdvancedTab.swift:10-23; Sources/SeshatAppKit/Settings/AdvancedTab.swift:77-103; Sources/SeshatAppKit/Settings/AdvancedTab.swift:137-186 |

## Detailed findings

### Item 1 — Do-not-diverge paragraph
Status: PASS

The required paragraph is present verbatim at the top of the file and repeated under `## Critical discipline`. plans/CENTRAL_LAYERS_PROMPT.md:13-15; plans/central/LAYER_2_storage.md:1-6.

### Item 2 — Locked decisions from master prompt §Layer 2
Status: PARTIAL
Severity: minor

All Layer 2 scope bullets are represented semantically, but they are not preserved verbatim or surfaced as `[QUESTION]` rewrites. The plan compresses prompt bullets into shorthand such as ``StorageLocator protocol surface: url(for:), baseDirectory, ensureDirectoriesExist()`` and ``Rename SeshatConfig → AppConfig OR integrate its responsibilities into StorageLocator`` instead of keeping the prompt wording intact. That weakens traceability for a section the brief treats as locked. plans/CENTRAL_LAYERS_PROMPT.md:186-202; plans/central/LAYER_2_storage.md:13-23; plans/central/LAYER_2_storage.md:42-58; plans/central/LAYER_2_storage.md:206-208.

No prompt bullet from `plans/CENTRAL_LAYERS_PROMPT.md:186-202` was found completely absent in `plans/central/LAYER_2_storage.md`; the issue is paraphrase, not omission.

### Item 3 — Three-stage structure
Status: PARTIAL
Severity: major

The plan does have explicit Stage 1, Stage 2, and Stage 3 sections with numbered steps. The implementability problem is the Stage 3 execution contract: the file says deletion runs only during `plans/central/INDEX.md`'s global deletion pass, but that prompt-mandated coordinating file is absent on trunk. As written, Step `2.13` cannot be executed verbatim end-to-end. plans/CENTRAL_LAYERS_PROMPT.md:42-54; plans/CENTRAL_LAYERS_PROMPT.md:75-78; plans/central/LAYER_2_storage.md:69-173.

### Item 4 — Validation checklists per step
Status: FAIL
Severity: major

The prompt requires every step to carry a validation checklist tied to specific `file:line` anchors and plan clauses. Layer 2 instead has a single aggregated checklist at the end. Steps `2.1` through `2.13` do not each have their own box-by-box validation block, so the file does not satisfy the prompt's per-step audit contract. plans/CENTRAL_LAYERS_PROMPT.md:11-17; plans/central/LAYER_2_storage.md:76-173; plans/central/LAYER_2_storage.md:186-201.

### Item 5 — Forbidden duplicates semantic audit
Status: PARTIAL
Severity: minor

The plan explicitly introduces one semantic duplicate under a new name: `AppConfig` becomes canonical while `SeshatConfig` remains a forwarding compatibility shim until Stage 3. That overlap is acknowledged in the plan, so this is not silent duplication, but it is still duplicate ownership of storage/config facts until deletion completes. Current trunk already contains both surfaces and duplicated base-directory resolution paths. plans/central/LAYER_2_storage.md:25; plans/central/LAYER_2_storage.md:45; plans/central/LAYER_2_storage.md:65; plans/central/LAYER_2_storage.md:105; plans/central/LAYER_2_storage.md:171-173; Sources/SeshatCore/Config.swift:3-63; Sources/SeshatCore/Storage/AppConfig.swift:3-65; Sources/SeshatCore/Storage/AppStorageLocator.swift:26-51.

### Item 6 — Parallel-build collision rule
Status: FAIL
Severity: major

This is the most important trunk mismatch. The plan says Stage 1 introduces a new `Sources/SeshatCore/Storage/` directory and new tests under `Tests/SeshatCoreTests/Storage/`, but those directories and the named Stage 1 files already exist on current trunk. The Stage 1 lane is therefore no longer a "build in parallel in NEW directories" lane that can be executed verbatim. plans/CENTRAL_LAYERS_PROMPT.md:44-59; plans/central/LAYER_2_storage.md:22; plans/central/LAYER_2_storage.md:76-95; Sources/SeshatCore/Storage/ManagedDirectory.swift:1-13; Sources/SeshatCore/Storage/StorageLocator.swift:1-7; Sources/SeshatCore/Storage/AppStorageLocator.swift:1-52; Sources/SeshatCore/Storage/AppConfig.swift:1-65; Sources/SeshatCore/Storage/AtomicFileWriter.swift:1-8; Sources/SeshatCore/Storage/FileManagerAtomicFileWriter.swift:1-69; Sources/SeshatCore/Storage/DiskSpaceSnapshot.swift:1-48; Tests/SeshatCoreTests/Storage/StorageLocatorTests.swift:5-145; Tests/SeshatCoreTests/Storage/AtomicFileWriterTests.swift:5-90; Tests/SeshatCoreTests/Storage/DiskSpaceSnapshotTests.swift:5-58; Tests/SeshatCoreTests/Storage/AppConfigTests.swift:5-65.

Current trunk is also already beyond the plan's "unblocked after this stage" posture: Layer 6 code is checked in and depends on `StorageLocator` / `AppConfig` today. plans/central/LAYER_2_storage.md:100; Sources/SeshatSession/Models/Selection/DefaultModelService.swift:20-42; Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:18-31; Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:214-221.

### Item 7 — Behavior-neutral Stages 1–3
Status: PASS

The plan keeps the on-disk app-support root as `~/Library/Application Support/Seshat/` and explicitly defers key renames to Layer 3. No `personal_scribe` or `Ninimma` pre-flip is proposed in Stages 1-3. plans/central/LAYER_2_storage.md:61; plans/central/LAYER_2_storage.md:95.

### Item 8 — `[QUESTION]` markers preserved
Status: PASS

The two open questions the brief called out remain explicit: model staging ownership (`models/` adjacency vs `cache/`) and whether `logs/` is only a reserved root or a later diagnostics surface. They were not silently resolved away. plans/central/LAYER_2_storage.md:182-185.

### Item 9 — Inter-layer dependencies
Status: PARTIAL
Severity: major

Layer 2's dependency section is consistent with Layers 3, 6, and 8: those plans all explicitly wait on the storage/path service before their own relevant swaps. The mismatch is Layer 7. The prompt says Layer 2 blocks Layer 7 because pipeline config lives in `modes/`, and Layer 2 repeats that dependency, but Layer 7's inter-layer dependency section requires only Layers 5 and 6. That leaves the `modes/` ownership dependency unmirrored. plans/CENTRAL_LAYERS_PROMPT.md:201-202; plans/central/LAYER_2_storage.md:206-208; plans/central/LAYER_3_settings.md:9-12; plans/central/LAYER_6_model_selection.md:95-97; plans/central/LAYER_6_model_selection.md:123; plans/central/LAYER_6_model_selection.md:247-249; plans/central/LAYER_7_pipeline.md:373-375; plans/central/LAYER_8_metrics.md:115; plans/central/LAYER_8_metrics.md:177-178.

### Item 10 — File:line citation freshness
Status: PASS

Five representative source anchors still match current trunk:

- `plans/central/LAYER_2_storage.md:30` matches `Sources/SeshatCore/Config.swift:13-106` for base-directory resolution, override precedence, and managed subdirectory helpers.
- `plans/central/LAYER_2_storage.md:31` matches `Sources/SeshatCore/TranscriptStore.swift:30-75` for `TranscriptStoreJSONL` bootstrap, `0600` permissions, and append flow.
- `plans/central/LAYER_2_storage.md:32` matches `Sources/SeshatCore/SQLiteTranscriptStore.swift:33-60` and `Sources/SeshatCore/SQLiteTranscriptStore.swift:204-229` for recordings-path derivation and tmp bootstrap/rename.
- `plans/central/LAYER_2_storage.md:33` matches `Sources/SeshatCore/BaseDirectoryMigrator.swift:58-126` and `Sources/SeshatCore/BaseDirectoryMigrator.swift:174-193` for managed-directory enumeration, writability probe, and rollback.
- `plans/central/LAYER_2_storage.md:38` matches `Sources/SeshatAppKit/Settings/AdvancedTab.swift:10-23`, `Sources/SeshatAppKit/Settings/AdvancedTab.swift:77-103`, and `Sources/SeshatAppKit/Settings/AdvancedTab.swift:137-186` for direct base-directory resolution plus hard-coded `models` / `modes` / `recordings` copy.

No stale `file:line` anchors were found in those five representative spot-checks.

## Cross-layer concerns

- Global deletion-pass concern: Layer 2 Stage 3 defers to `plans/central/INDEX.md`, but that prompt-mandated file is missing on trunk. This affects any layer expecting repo-wide Stage 3 coordination, not just Layer 2. plans/CENTRAL_LAYERS_PROMPT.md:75-78; plans/central/LAYER_2_storage.md:165-166.
- Layer 1: no conflict observed. Layer 1 blocks Layers 4, 5, and 9 through permission-state centralization and does not claim storage/path ownership. plans/central/LAYER_1_permissions.md:241-243.
- Layer 3: no conflict observed. Layer 3 explicitly waits on Layer 2 for the `BaseDirectoryPath` resolver work. plans/central/LAYER_3_settings.md:9-12; plans/central/LAYER_3_settings.md:101.
- Layer 4: no direct storage-content conflict observed in the actual AppStore plan, but the plan set diverges from the prompt deliverable name. The prompt requires `plans/central/LAYER_4_state_store.md`; trunk instead contains `plans/central/LAYER_4_appstore.md`. That breaks prompt-to-plan traceability for any layer referencing the required filename. plans/CENTRAL_LAYERS_PROMPT.md:75-86; plans/CENTRAL_LAYERS_PROMPT.md:234; plans/central/LAYER_4_appstore.md:1-7; plans/central/LAYER_4_appstore.md:255-277.
- Layer 5: no conflict observed. Layer 5 depends on Layers 1 and 3, not Layer 2. plans/central/LAYER_5_output.md:412-415.
- Layer 6: no written-plan conflict, but trunk is already ahead of the Layer 2 plan. The Layer 6 plan depends on StorageLocator/AppConfig, and current code already implements that dependency. That makes Layer 2's Stage 1 "introduce new storage namespace" story historical rather than future. plans/central/LAYER_6_model_selection.md:95-97; plans/central/LAYER_6_model_selection.md:123; plans/central/LAYER_6_model_selection.md:247-249; Sources/SeshatSession/Models/Selection/DefaultModelService.swift:20-42; Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:18-31; Sources/SeshatTranscription/Models/Selection/ModelAwareFluidAudioTranscriber.swift:214-221.
- Layer 7: conflict observed. Layer 2 says it blocks Layer 7 because pipeline config lives in `modes/`, but Layer 7's dependency section omits Layer 2 entirely. plans/CENTRAL_LAYERS_PROMPT.md:201-202; plans/central/LAYER_2_storage.md:206-208; plans/central/LAYER_7_pipeline.md:373-375.
- Layer 8: no conflict observed. Layer 8 explicitly requires Layer 2 Stage 2 for centralized recordings-path wiring. plans/central/LAYER_8_metrics.md:115; plans/central/LAYER_8_metrics.md:177-178.
- Layer 9: no conflict observed. Layer 9 only requires Layer 1. plans/central/LAYER_9_app_brand.md:256-258.

## Stale file:line citations

No stale `file:line` citations were found in the five representative trunk spot-checks listed under Item 10:

- plans/central/LAYER_2_storage.md:30 -> Sources/SeshatCore/Config.swift:13-106
- plans/central/LAYER_2_storage.md:31 -> Sources/SeshatCore/TranscriptStore.swift:30-75
- plans/central/LAYER_2_storage.md:32 -> Sources/SeshatCore/SQLiteTranscriptStore.swift:33-60 and Sources/SeshatCore/SQLiteTranscriptStore.swift:204-229
- plans/central/LAYER_2_storage.md:33 -> Sources/SeshatCore/BaseDirectoryMigrator.swift:58-126 and Sources/SeshatCore/BaseDirectoryMigrator.swift:174-193
- plans/central/LAYER_2_storage.md:38 -> Sources/SeshatAppKit/Settings/AdvancedTab.swift:10-23, Sources/SeshatAppKit/Settings/AdvancedTab.swift:77-103, and Sources/SeshatAppKit/Settings/AdvancedTab.swift:137-186
