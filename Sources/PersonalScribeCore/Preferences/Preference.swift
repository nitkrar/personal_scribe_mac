import Foundation
import SwiftUI

public struct Preference<Value: Codable & Sendable> {
    public let key: String
    public let `default`: Value
    public let defaults: UserDefaults

    public init(
        key: String,
        default defaultValue: Value,
        defaults: UserDefaults
    ) {
        self.key = key
        self.default = defaultValue
        self.defaults = defaults
    }

    public func resolve() -> Value {
        PreferenceCodec.resolve(
            Value.self,
            key: key,
            default: `default`,
            defaults: defaults
        )
    }

    public func persist(_ value: Value) {
        PreferenceCodec.persist(value, key: key, defaults: defaults)
    }

    @MainActor
    public func binding() -> Binding<Value> {
        Binding(
            get: { resolve() },
            set: { persist($0) }
        )
    }
}

private enum PreferenceCodec {
    static func resolve<Value: Codable & Sendable>(
        _: Value.Type,
        key: String,
        default defaultValue: Value,
        defaults: UserDefaults
    ) -> Value {
        guard
            let object = defaults.object(forKey: key),
            let data = encodedData(from: object),
            let value = try? JSONDecoder().decode(Value.self, from: data)
        else {
            return defaultValue
        }
        return value
    }

    static func persist<Value: Codable & Sendable>(
        _ value: Value,
        key: String,
        defaults: UserDefaults
    ) {
        guard let data = try? JSONEncoder().encode(value) else {
            return
        }

        switch storageAction(for: data) {
        case .remove:
            defaults.removeObject(forKey: key)
        case .store(let object):
            defaults.set(object, forKey: key)
        }
    }

    private static func encodedData(from object: Any) -> Data? {
        if let data = object as? Data {
            return data
        }

        return try? JSONSerialization.data(
            withJSONObject: object,
            options: [.fragmentsAllowed]
        )
    }

    private static func storageAction(for data: Data) -> StorageAction {
        guard
            let object = try? JSONSerialization.jsonObject(
                with: data,
                options: [.fragmentsAllowed]
            )
        else {
            return .store(data)
        }

        switch object {
        case is NSString, is NSNumber:
            // Preserve existing resolver formats: scalar codables stay as
            // UserDefaults scalars, composite codables stay as JSON Data.
            return .store(object)
        case is NSNull:
            return .remove
        default:
            return .store(data)
        }
    }

    private enum StorageAction {
        case store(Any)
        case remove
    }
}
