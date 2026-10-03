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
/// Decoding `.setting` looks the key up in `PreferenceKeys`; unknown
/// keys fail to decode.
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
            guard let registered = PreferenceKeys.registered(key, as: Value.self) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .key,
                    in: container,
                    debugDescription: "Unregistered setting key \(key)"
                )
            }
            self = .setting(registered)
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
