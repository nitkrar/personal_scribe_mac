# Layer 3 Stage 1 Code Review

## 1. Verdict

APPROVE-WITH-NITS

The implementation matches the locked Stage `3.1` wrapper surface from `plans/central/LAYER_3_settings.md:41` with stored `key`, stored `default`, injected `defaults`, `resolve()`, `persist(_)`, and `@MainActor binding() -> Binding<Value>`, and it keeps the work isolated to `Sources/SeshatCore/Preferences/` and `Tests/SeshatCoreTests/Preferences/` exactly as Stage `3.1` and the prior review required (`plans/central/LAYER_3_settings.md:65-72`; `plans/central/reviews/LAYER_3_review.md:18-19`, which says "The Stage 1 collision rule is honored."). `Sources/SeshatCore/Preferences/Preference.swift:19-112` and `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:27-157` correctly cover missing-key fallback, decode-error fallback, scalar / enum / struct round-trips, and binding write-through, and the current teardown at `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:21-23` resolves the Swift 6 sendability issue that was fixed forward after the primary landing. The remaining issues are coverage-only: the new wrapper suite proves the generic paths with synthetic types, but it does not directly pin the concrete `HotkeyPreference` payload or any of the in-scope settings enums called out by the plan's `[QUESTION]` items.

## 2. Findings by severity

### Blocker

None.

### Major

None.

### Minor

1. `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:11-14,102-115`

   Quote:
   ```swift
   private struct TestPreferenceStruct: Codable, Sendable, Equatable {
       let keyCode: UInt16
       let tapCount: Int
   }
   ...
   func testPersistRoundTripsStructsUsingDataStorage() {
       let defaults = isolatedDefaults()
       let preference = Preference<TestPreferenceStruct>(
           key: "StructPreference",
           default: TestPreferenceStruct(keyCode: 61, tapCount: 2),
           defaults: defaults
       )
   ```

   The Stage 1 matrix says "`Preference<HotkeyPreference>` preserves `Codable` structs" (`plans/central/LAYER_3_settings.md:82`), and the paired `[QUESTION]` item is specifically about "`HotkeyPreference` already conforms to `Codable`, but the persisted payload is safe only because the stored fields are scalar-only" (`plans/central/LAYER_3_settings.md:143`). The new suite proves the generic struct path with a two-field stand-in, but it never instantiates `Preference<HotkeyPreference>`, so the exact three-field payload that Stage `3.6` will migrate is not pinned at the wrapper layer.

### Nit

1. `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:6-9,74-86`

   Quote:
   ```swift
   private enum TestPreferenceEnum: String, Codable, Sendable {
       case alpha
       case beta
   }
   ...
   func testPersistRoundTripsRawValueEnumsUsingScalarStorage() {
       let defaults = isolatedDefaults()
       let preference = Preference<TestPreferenceEnum>(
           key: "EnumPreference",
           default: .alpha,
           defaults: defaults
       )
   ```

   The suite proves raw-value enum behavior generically, but the plan's `[QUESTION]` item is about the concrete settings enums: "Confirm that adding `Codable` is acceptable and that all in-scope cases stay raw-value-only" (`plans/central/LAYER_3_settings.md:142`). Because this test never touches one of the real raw strings that Stage `3.2`, `3.3`, and `3.5` will migrate, the concrete enum compatibility risk is still deferred to those per-resolver steps.

## 3. Cross-layer concerns

- `Sources/SeshatCore/Preferences/Preference.swift:19-30` is intentionally storage-only. That matches the plan's requirement that "`semantic types keep their behavior`" (`plans/central/LAYER_3_settings.md:45`), but it also means Stage `3.4` and `3.6` must keep `PasteRestoreDelay` sanitization / clamping and `HotkeyPreference.isSupported` outside the generic wrapper. Future Layer 5+ consumers should keep going through typed façades where validation matters instead of assuming `Preference` enforces those semantics itself.
- `Sources/SeshatCore/Preferences/Preference.swift:67-72,101-103` already implements the `NSNull` -> `removeObject` path that future `BaseDirectoryPath = Preference<String?>` adoption would rely on (`plans/central/LAYER_3_settings.md:58`), so the code does not hard-block Layer 2. That behavior is just not pinned by a Stage 1 wrapper test yet.
- The prior plan review flagged a plan-level Layer 6 conflict because Layer 3 reserved `Preference<String>` for `ActiveModelDescriptor` while Layer 6 wanted `Preference<ActiveModelDescriptor>` (`plans/central/reviews/LAYER_3_review.md:20-21,27-28`). The shipped Stage 1 implementation is generic over `Value: Codable & Sendable` and does not bake in the `String` choice, so that earlier conflict is not present in the code reviewed here.

## 4. Test gaps

- `[QUESTION] enum Codable synthesis` (`plans/central/LAYER_3_settings.md:142`): `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:6-9,74-86` exercises a synthetic raw-value enum only. The concrete enum conformances and their real persisted raw strings still need regression coverage in Stage `3.2`, `3.3`, and `3.5`.
- `[QUESTION] HotkeyPreference scalar-only payload` (`plans/central/LAYER_3_settings.md:143`): `Tests/SeshatCoreTests/Preferences/PreferenceTests.swift:11-14,102-115` exercises a synthetic struct only. If the team wants that concern pinned at the generic-wrapper layer, add a direct `Preference<HotkeyPreference>` round-trip instead of relying only on the older `HotkeyPreference` tests.

## 5. Summary

Verdict remains `APPROVE-WITH-NITS`.

Finding counts:
- Blocker: 0
- Major: 0
- Minor: 1
- Nit: 1

Overall readiness for Stage 2: ready. The implementation is plan-faithful, Stage 1-scoped, and concurrency-safe in its current form; the only follow-up I would require is direct coverage for the concrete enum and `HotkeyPreference` migrations when those resolver-specific Stage 2 steps land.
