import Foundation

/// User-selectable delay before the pre-paste clipboard is restored.
///
/// Stored in `UserDefaults` at `SeshatPasteRestoreDelaySeconds`. The default
/// remains `0.5` seconds so existing paste-at-cursor behaviour keeps a short
/// delay unless a user explicitly chooses a different value.
public struct PasteRestoreDelay: Sendable, Equatable {
    public let seconds: TimeInterval

    public static let `default`: PasteRestoreDelay = .init(seconds: 0.5)
    public static let userDefaultsKey = "SeshatPasteRestoreDelaySeconds"

    private static let minimumSeconds: TimeInterval = 0.1
    private static let maximumSeconds: TimeInterval = 5.0

    public init(seconds: TimeInterval) {
        self.seconds = seconds
    }

    public static func resolve(from defaults: UserDefaults = .standard) -> PasteRestoreDelay {
        guard let object = defaults.object(forKey: userDefaultsKey) else {
            return .default
        }
        guard let seconds = decodeSeconds(from: object) else {
            return .default
        }
        return PasteRestoreDelay(seconds: clamp(seconds))
    }

    public static func persist(
        to defaults: UserDefaults = .standard,
        _ delay: PasteRestoreDelay
    ) {
        defaults.set(sanitizedSeconds(delay.seconds), forKey: Self.userDefaultsKey)
    }

    private static func decodeSeconds(from object: Any) -> TimeInterval? {
        guard let number = object as? NSNumber else {
            return nil
        }
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let seconds = number.doubleValue
        guard seconds.isFinite else {
            return nil
        }
        return seconds
    }

    private static func sanitizedSeconds(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else {
            return `default`.seconds
        }
        return clamp(seconds)
    }

    private static func clamp(_ seconds: TimeInterval) -> TimeInterval {
        max(minimumSeconds, min(seconds, maximumSeconds))
    }
}
