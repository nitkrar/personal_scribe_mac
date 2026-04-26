import Foundation

/// Sum type for a recipe-piece parameter (per #078 L19 + L22).
///
/// Each parameter on a `CaptureControllerSpec` / `OutputSinkSpec` /
/// `ProcessorSpec` carries either:
///
/// - `.setting(SettingKey<Value>)` — defer to a global preference.
///   Resolves to whatever the user has persisted under that key,
///   falling back to the registry-declared hardcoded default.
/// - `.override(Value)` — force a per-mode value. Wins regardless of
///   what the underlying setting says.
///
/// Resolution rule (L19): `.override` > `.setting` > hardcoded default.
/// Resolution is **eager** at piece-construction (L25), implemented by
/// `ParameterResolver`. There is no lazy path; once a `RecipeBuilder`
/// hands an orchestrator a bound `BoundRecipe`, the parameter is a
/// concrete `Value` for the duration of the session.
///
/// Codable shape (per L22):
/// - `.setting`: `{"source": "setting", "key": "VadSilenceDurationSeconds"}`
/// - `.override`: `{"source": "override", "value": 2.5}`
///
/// On decode of `.setting`, the resulting `SettingKey` carries the
/// decoded key paired with a placeholder default value; the
/// `ParameterResolver` tolerates this by accepting a `defaults:
/// UserDefaults` and reading the persisted scalar — when the persisted
/// scalar is absent the resolver returns the in-memory `default` of
/// the `SettingKey` (which production code re-pairs with the central
/// `PreferenceKeys` registry before resolving). Tests that exercise
/// `Parameter` Codable round-trip therefore pin the case + key only;
/// tests that exercise `ParameterResolver` separately pin the
/// per-source resolution rule.
///
/// `Value: Codable & Sendable` matches `SettingKey`'s constraints and
/// keeps recipe documents (`WorkflowModeDocument`) round-trippable.
public enum Parameter<Value: Codable & Sendable>: Sendable {
    case setting(SettingKey<Value>)
    case override(Value)
}

extension Parameter: Codable {
    private enum CodingKeys: String, CodingKey {
        case source
        case key
        case value
        // Optional default-roundtrip companion to `key` so that
        // round-tripped `.setting` parameters retain the in-memory
        // default. Encoded as a sibling of `key` for the `.setting`
        // case; absent for `.override`. Tolerates older / external
        // documents that omit it (decoder keeps the placeholder).
        case settingDefault
    }

    private enum Source: String, Codable {
        case setting
        case override
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let source = try container.decode(Source.self, forKey: .source)
        switch source {
        case .setting:
            let key = try container.decode(String.self, forKey: .key)
            // Round-trip companion (optional). When missing, the
            // resolver consults the central registry to re-pair the
            // hardcoded default with this key.
            let placeholder = try container.decodeIfPresent(
                Value.self,
                forKey: .settingDefault
            )
            // Without a placeholder we cannot construct a SettingKey
            // because Value is not default-initializable in the type
            // system. Decode is therefore strict: round-trip requires
            // the companion. Production-side, recipes only encode/
            // decode through round-trip pipelines we control, so the
            // companion is always present.
            guard let defaultValue = placeholder else {
                throw DecodingError.dataCorruptedError(
                    forKey: .settingDefault,
                    in: container,
                    debugDescription: "Parameter.setting requires a `settingDefault` companion to reconstruct the SettingKey default."
                )
            }
            self = .setting(SettingKey(key: key, default: defaultValue))
        case .override:
            let value = try container.decode(Value.self, forKey: .value)
            self = .override(value)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .setting(let settingKey):
            try container.encode(Source.setting, forKey: .source)
            try container.encode(settingKey.key, forKey: .key)
            try container.encode(settingKey.default, forKey: .settingDefault)
        case .override(let value):
            try container.encode(Source.override, forKey: .source)
            try container.encode(value, forKey: .value)
        }
    }
}

extension Parameter: Equatable where Value: Equatable {
    public static func == (lhs: Parameter<Value>, rhs: Parameter<Value>) -> Bool {
        switch (lhs, rhs) {
        case let (.setting(a), .setting(b)):
            return a.key == b.key && a.default == b.default
        case let (.override(a), .override(b)):
            return a == b
        default:
            return false
        }
    }
}
