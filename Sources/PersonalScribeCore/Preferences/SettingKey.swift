import Foundation

/// Identity for a global preference referenced by `Parameter<Value>`'s
/// `.setting(...)` case. A `SettingKey<Value>` is a thin, value-typed
/// wrapper around the existing `Preference<Value>` mechanism: the same
/// `String` UserDefaults key, the same hardcoded `default` fallback, the
/// same Codable resolver via `PreferenceCodec`. The wrapper exists so
/// recipes (`WorkflowMode`) can serialise `{source: "setting",
/// key: "..."}` per L22 without baking a `Preference` instance into the
/// recipe — settings are referred to by key, not by binding.
///
/// Why thin: `Preference<Value>` already owns the encode/decode +
/// scalar/data-storage routing logic. Recreating that here would
/// duplicate `PreferenceCodec`. `SettingKey.resolve(from:)` instead
/// delegates to a freshly-constructed `Preference<Value>` for the call —
/// equivalent semantics with zero divergence risk.
///
/// Sendable: `Value: Codable & Sendable` matches `Preference`'s
/// constraint. `SettingKey` is itself a value type with `String` +
/// `Value` defaults, so it crosses concurrency boundaries trivially.
public struct SettingKey<Value: Codable & Sendable>: Sendable {
    /// UserDefaults key. Matches the existing `Preference<Value>.key`
    /// for a given setting — recipes referencing a `SettingKey` resolve
    /// to the same scalar/Data on disk that the legacy `Preference`
    /// reads/writes.
    public let key: String

    /// Hardcoded fallback returned when no value is persisted under
    /// `key`. Matches the existing `Preference<Value>.default` field.
    public let `default`: Value

    /// Applied to every resolved and persisted value.
    public let sanitize: @Sendable (Value) -> Value

    public init(
        key: String,
        default defaultValue: Value,
        sanitize: @escaping @Sendable (Value) -> Value = { $0 }
    ) {
        self.key = key
        self.default = defaultValue
        self.sanitize = sanitize
    }

    /// Resolve the current value from the supplied `UserDefaults`
    /// suite, falling back to `default` when the key is absent or the
    /// stored value fails to decode. Mirrors `Preference.resolve()`.
    public func resolve(from defaults: UserDefaults) -> Value {
        sanitize(preference(defaults).resolve())
    }

    public func persist(_ value: Value, to defaults: UserDefaults) {
        preference(defaults).persist(sanitize(value))
    }

    private func preference(_ defaults: UserDefaults) -> Preference<Value> {
        Preference(key: key, default: `default`, defaults: defaults)
    }
}
