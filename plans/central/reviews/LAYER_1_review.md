# Layer 1 Review

Verdict: NEEDS REVISION

Finding summary: critical 2, major 4, minor 0.

## Findings by checklist item

1. PASS — The do-not-diverge paragraph is present verbatim at the top of the plan under `## Critical discipline` in `plans/central/LAYER_1_permissions.md:3-4`, matching `plans/CENTRAL_LAYERS_PROMPT.md:13-17`.

2. FAIL — The locked Layer 1 bullets are mostly restated semantically, not carried forward verbatim as required by the audit scope; the clearest divergence is `the onboarding flow` in place of `OnboardingViewModel (or its successor in the Permissions sub-tab)`.
Reference: `plans/central/LAYER_1_permissions.md:44-56`. The Layer 1 scope bullets at `plans/CENTRAL_LAYERS_PROMPT.md:160-177` are not reproduced verbatim, and `plans/central/LAYER_1_permissions.md:53` paraphrases the locked migration bullet instead of preserving its exact text or marking a `[QUESTION]`.

3. FAIL — The plan uses numbered Stage 1 / Stage 2 / Stage 3 steps, but it keeps a layer-local deletion step instead of deferring deletions to the global INDEX deletion pass the master prompt requires.
Reference: `plans/central/LAYER_1_permissions.md:201-213`. This conflicts with `plans/CENTRAL_LAYERS_PROMPT.md:50-54`, which says every layer must defer Stage 3 deletions to `INDEX.md`'s global `Stage 3 — Deletion pass` section.

4. FAIL — Every step has a validation checklist, but several checklist bullets are still bare prose assertions without `file:line` anchors.
Reference: `plans/central/LAYER_1_permissions.md:108-112` and `plans/central/LAYER_1_permissions.md:123-126`. Examples include the `refresh()` / `@Published` assertion at line 110 and the one-consumer-per-step assertion at line 126, which cite prompt clauses but no concrete code locations.

5. FAIL — The plan does not perform the required semantic duplicate audit, and Step 1.1 introduces a new `PermissionStatus` in a location where trunk already has one.
Reference: `plans/central/LAYER_1_permissions.md:83`. Trunk already contains `PermissionStatus` at `Sources/SeshatCore/Permissions/PermissionStatus.swift:1-4`, so the plan needs an explicit semantic-owner inventory instead of silently proposing another `PermissionStatus` under the same semantic role and directory.

6. FAIL — The Stage 1 collision rule is not honored: both claimed Stage 1 source directories already exist in trunk, and the core collision is not surfaced as a `[QUESTION]`.
Reference: `plans/central/LAYER_1_permissions.md:80-83` and `plans/central/LAYER_1_permissions.md:96-106`. `Sources/SeshatCore/Permissions/PermissionStatus.swift:1-4` already occupies the planned core directory, and `Sources/SeshatAppKit/Permissions/SeshatAppKitPermissionsModule.swift:1` plus `Sources/SeshatAppKit/Permissions/AppKitMicrophonePermissionRequester.swift:4-56` already occupy the AppKit directory, which violates the `NEW files, in NEW directories` rule from `plans/CENTRAL_LAYERS_PROMPT.md:44-59`.

7. PASS — Stages 1-3 stay behavior-neutral with respect to the later rename pass; the plan does not pre-bake post-Stage-3 values such as `Ninimma`, `PS`, or `personal_scribe`.

8. PARTIAL — The plan surfaces two real ambiguities, but it misses the more immediate core-path collision and silently plans over it.
Reference: `plans/central/LAYER_1_permissions.md:83` and `plans/central/LAYER_1_permissions.md:222-224`. The AppKit `Permissions/` collision is marked with `[QUESTION]`, but the existing `Sources/SeshatCore/Permissions/PermissionStatus.swift:1-4` collision is not.

9. PASS — The bottom dependency section is present and broadly consistent with sibling plans that consume Layer 1, especially `plans/central/LAYER_5_output.md:413-415` and `plans/central/LAYER_9_app_brand.md:175-184`.

10. PARTIAL — The plan contains a mix of fresh and stale citations; the repeated references to `Sources/SeshatCore/PermissionStatus.swift` no longer match trunk, while other spot-checked citations still do.
Reference: `plans/central/LAYER_1_permissions.md:7`, `plans/central/LAYER_1_permissions.md:15`, `plans/central/LAYER_1_permissions.md:73`, `plans/central/LAYER_1_permissions.md:83`, and `plans/central/LAYER_1_permissions.md:102`. The stale file path should be updated to the current split locations in trunk.

## Cross-layer concerns

None identified. Layer 1's bottom-level dependency claims are compatible with the current sibling-layer contracts in `plans/central/LAYER_5_output.md:413-415`, `plans/central/LAYER_3_settings.md:122-123`, and `plans/central/LAYER_9_app_brand.md:175-184`.

## Stale file:line citations

- `plans/central/LAYER_1_permissions.md:7` cites `Sources/SeshatCore/PermissionStatus.swift:6-44`, but trunk has no `Sources/SeshatCore/PermissionStatus.swift`. The Input Monitoring types now live at `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:6-44`, and the shared `PermissionStatus` enum already exists at `Sources/SeshatCore/Permissions/PermissionStatus.swift:1-4`.
- `plans/central/LAYER_1_permissions.md:15` cites `Sources/SeshatCore/PermissionStatus.swift:6-44` for `InputMonitoringPermissionState`, `PermissionProbing`, and `IOHIDPermissionProbe`; trunk state is `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:6-44`.
- `plans/central/LAYER_1_permissions.md:73` cites `Sources/SeshatCore/PermissionStatus.swift:16-25` for the `IOHIDCheckAccess` caveat; trunk state is `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:16-25`.
- `plans/central/LAYER_1_permissions.md:83` cites `Sources/SeshatCore/PermissionStatus.swift:6-44` as the IM-only legacy surface; trunk state is split between `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:6-44` and `Sources/SeshatCore/Permissions/PermissionStatus.swift:1-4`.
- `plans/central/LAYER_1_permissions.md:91` and `plans/central/LAYER_1_permissions.md:94` repeat the same stale `Sources/SeshatCore/PermissionStatus.swift:6-44` citation; the current trunk locations are unchanged from the bullets above.
- `plans/central/LAYER_1_permissions.md:138-139` again cite `Sources/SeshatCore/PermissionStatus.swift:12-25`; trunk state is `Sources/SeshatCore/InputMonitoringPermissionProbe.swift:12-25`.
