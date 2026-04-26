import Foundation

/// Single resolution point for `Parameter<Value>` (per #078 L19/L22).
///
/// Resolution rule:
/// 1. `.override(value)` → `value` (per-mode wins).
/// 2. `.setting(key)` → `key.resolve(from: defaults)` (UserDefaults read,
///    falls back to the `SettingKey`'s registered hardcoded default).
///
/// Eager-at-call-site (L25): `ParameterResolver.resolve(_:from:)` is
/// called once when `RecipeBuilder` constructs a `BoundRecipe` at
/// session start. The returned `Value` is captured into the bound
/// pieces; mid-session UserDefaults / setActive changes do not affect
/// the in-flight session.
///
/// Caseless enum: namespace only. There is no resolver state — the
/// rule is a pure switch on the parameter's case. Centralisation here
/// (vs. a per-piece resolution helper) is the L19 lock: "Resolution
/// lives in one place, not per-piece."
public enum ParameterResolver {
    /// Resolve a `Parameter<Value>` to a concrete `Value`.
    ///
    /// - Parameters:
    ///   - parameter: the recipe-declared parameter.
    ///   - defaults: UserDefaults suite for `.setting` lookup. Pass
    ///     `.standard` in production; tests pass an isolated suite.
    /// - Returns: the per-mode override value when present, otherwise
    ///   the persisted setting value (or its hardcoded default).
    public static func resolve<Value: Codable & Sendable>(
        _ parameter: Parameter<Value>,
        from defaults: UserDefaults
    ) -> Value {
        switch parameter {
        case .override(let value):
            return value
        case .setting(let key):
            return key.resolve(from: defaults)
        }
    }
}
