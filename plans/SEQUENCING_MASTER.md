# Sequencing Master

## Phase order
- Execute the rename pass completely before Phase 1. Phase 1 assumes the post-rename symbols and defaults-key spellings from [plans/rename/PLAN.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/rename/PLAN.md) (which supersedes the earlier `plans/PHASE_0_rename.md`).
- Execute Phase 1 service work (`1.1` through `1.6`) completely before any Phase 2 UI work. Phase 2 assumes the unified permission service is already live from [plans/PHASE_1_permission_service.md](/Users/nitinkum/Projects/nitkrar/seshat/plans/PHASE_1_permission_service.md).
- Treat `1.7`, `1.8`, and `1.9` as sequencing placeholders only. They do not land on the Phase 1 branch; they transfer directly into Phase 2 steps `2.7`, `2.8`, and `2.10`.
- Manus answers feed in only at the explicitly blocked steps:
  - `Q.M6` gates `2.5` (Transcriptions interaction).
  - `Q.M5` gates `2.6` (Modes CRUD semantics).
  - `Q.M1`, `Q.M2`, `Q.M3`, and `Q.M4` gate `2.7` (Settings consolidation), which in turn unblocks `2.8`.
- Before closing the affected Phase 2 steps, author/update the backlog docs named by locked decision `#1`: `plans/backlog/home-stats-metrics.md`, `plans/backlog/check-for-updates-sparkle.md`, `plans/backlog/mic-device-picker.md`, and `plans/backlog/launch-at-login-and-dock.md`.

## Ordered steps

| Step | 1-line summary | Depends on | Manus blocker |
| --- | --- | --- | --- |
| 0.1 | Rename the seven persisted `UserDefaults` keys and pin them with tests. | None | No |
| 0.2 | `git mv` the approved production types/files and mirrored test files. | 0.1 | No |
| 0.3 | Sweep repo-wide call sites, imports, comments, and test references onto the new names. | 0.2 | No |
| 0.4 | Run the rename verification sweep and close Phase 0 with no stragglers. | 0.1, 0.2, 0.3 | No |
| 1.1 | Define the shared `Permission` / `PermissionStatus` / `RequestOutcome` contract. | 0.4 | No |
| 1.2 | Implement the live AppKit permission-status probes and deep links. | 1.1 | No |
| 1.3 | Add relaunch-aware permission request semantics. | 1.2 | No |
| 1.4 | Publish one permission snapshot and refresh it on app activation. | 1.3 | No |
| 1.5 | Migrate menu bar, hotkey, and paste consumers onto the service. | 1.4 | No |
| 1.6 | Migrate onboarding/app-entry plumbing onto the service and make AX optional everywhere. | 1.5 | No |
| 1.7 | Preserve the handoff from onboarding rows to unified `Settings > Permissions`; do not implement on the Phase 1 branch. | 1.6; executes as 2.7 | Q.M1, Q.M2 |
| 1.8 | Preserve the handoff from onboarding routing to unified-window routing; do not implement on the Phase 1 branch. | 1.6; executes as 2.8 after 2.7 | Indirect via 2.7 (`Q.M1`, `Q.M2`) |
| 1.9 | Preserve the cleanup queue for legacy permission/requester surfaces; execute only in Phase 2 cleanup. | 1.8; executes as 2.10 | No |
| 2.1 | Replace the theme file and all call sites in one big-bang swap. | 1.6 | No |
| 2.2 | Ship the Manus menu layout, remove gating, and add the 0.6s recording icon timer. | 2.1 | No |
| 2.3 | Build the single-window `NavigationSplitView` shell and wire `Home` to it. | 2.2 | No |
| 2.4 | Fill the Home tab, with only the allowed metric stubs left blank. | 2.3 | No |
| 2.5 | Migrate history into the unified Transcriptions tab. | 2.3 | Q.M6 |
| 2.6 | Ship the persisted Modes tab CRUD scaffold, seeded with Dictation only. | 2.3 | Q.M5 |
| 2.7 | Consolidate Settings into General / Permissions / About, including the pill previews. | 2.1, 2.3, 1.6 | Q.M1, Q.M2, Q.M3, Q.M4 |
| 2.8 | Remove onboarding routing and make the unified window the only runtime surface. | 2.7, 2.3, 1.6 | Indirect via 2.7 |
| 2.9 | Finish the pill polish, keep `ResponseCard` scaffold-only, and remove any production caller. | 2.1, 1.6 | No |
| 2.10 | Delete the legacy windows, onboarding state, and old permission/requester leftovers. | 2.5, 2.6, 2.7, 2.8, 2.9, 1.9 | No |

## Manus handoff map

| Manus answer | First step that can legally consume it | Follow-on steps affected |
| --- | --- | --- |
| `Q.M6` Transcriptions interaction | `2.5` | `2.10` cleanup scope |
| `Q.M5` Modes CRUD semantics | `2.6` | `2.10` cleanup scope |
| `Q.M1` Settings control mapping | `2.7` | `1.7`, `1.8`, `2.8`, `2.10` |
| `Q.M2` Owner for `Show pill overlay` / `Show menu bar icon` | `2.7` | `1.7`, `1.8`, `2.8`, `2.10` |
| `Q.M3` About content spec | `2.7` | `2.10` cleanup scope |
| `Q.M4` `Mini` pill visual | `2.7` | none beyond `2.7` unless cleanup deletes a superseded preview helper |
